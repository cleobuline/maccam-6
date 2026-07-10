//
//  CAMEditorWindowController.m
//  cam-8
//

#import "CAMEditorWindowController.h"
#include "cam_forth.h"

@interface CAMEditorWindowController ()

@property (strong) NSTextView    *textView;
@property (strong) NSButton      *compileButton;
@property (strong) NSTextField   *statusLabel;

@end

@implementation CAMEditorWindowController

+ (instancetype)sharedEditor {
    static CAMEditorWindowController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CAMEditorWindowController alloc] init];
    });
    return instance;
}

- (instancetype)init {
    // Crée la fenêtre programmatiquement
    NSRect frame = NSMakeRect(100, 100, 500, 400);
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:NSWindowStyleMaskTitled |
                            NSWindowStyleMaskClosable |
                            NSWindowStyleMaskResizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = @"CAM-FORTH — Éditeur de règles";
    window.minSize = NSMakeSize(400, 300);

    self = [super initWithWindow:window];
    if (self) {
        [self _buildUI];
        [self _loadDefaultText];
    }
    return self;
}

- (void)_buildUI {
    NSView *content = self.window.contentView;
    NSRect bounds = content.bounds;

    // --- bouton Compiler ---
    _compileButton = [NSButton buttonWithTitle:@"⚡ Compiler & Lancer"
                                        target:self
                                        action:@selector(_compile)];
    _compileButton.frame = NSMakeRect(10, 10, 200, 32);
    _compileButton.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    [content addSubview:_compileButton];

    // --- label de statut ---
    _statusLabel = [NSTextField labelWithString:@"Prêt."];
    _statusLabel.frame = NSMakeRect(220, 14, bounds.size.width - 230, 24);
    _statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    [content addSubview:_statusLabel];

    // --- zone de texte avec scroll ---
    NSScrollView *scrollView = [[NSScrollView alloc]
        initWithFrame:NSMakeRect(0, 50, bounds.size.width, bounds.size.height - 50)];
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.borderType = NSNoBorder;

    _textView = [[NSTextView alloc]
        initWithFrame:NSMakeRect(0, 0, bounds.size.width, bounds.size.height - 50)];
    _textView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _textView.font = [NSFont fontWithName:@"Menlo" size:13.0];
    _textView.automaticQuoteSubstitutionEnabled = NO;
    _textView.automaticDashSubstitutionEnabled  = NO;
    _textView.richText = NO;
    _textView.backgroundColor = [NSColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:1.0];
    _textView.textColor = [NSColor colorWithRed:0.0 green:0.85 blue:1.0 alpha:1.0];
    _textView.insertionPointColor = [NSColor whiteColor];

    scrollView.documentView = _textView;
    [content addSubview:scrollView];
}

- (void)_loadDefaultText {
    NSString *defaultRule =
        @": SUM8\n"
        @"  NORTH SOUTH + EAST WEST + +\n"
        @"  N.EAST N.WEST + S.EAST S.WEST + + + ;\n"
        @"\n"
        @": MA-REGLE\n"
        @"  SUM8\n"
        @"  CENTER IF\n"
        @"    DUP 2 = SWAP 3 = OR\n"
        @"  ELSE\n"
        @"    3 =\n"
        @"  THEN ;\n"
        @"\n"
        @"MAKE-TABLE MA-REGLE\n";

    [_textView setString:defaultRule];
}

- (void)_compile {
    NSString *source = _textView.string;
    if (!source || source.length == 0) {
        _statusLabel.stringValue = @"⚠️ Source vide.";
        return;
    }

    // VM réinitialisée EN ENTIER à chaque compilation : la source décrit
    // toute la machine, rien ne doit fuir d'une compilation à l'autre.
    // L'ancien reset partiel (vm.dict_size = 0 seulement) laissait
    // traîner le VOISINAGE déclaré : compiler une règle N/MARG ou
    // N/CUSTOM puis une règle sans déclaration recompilait la seconde
    // dans le voisinage de la première, avec des offsets périmés.
    static ForthVM vm;
    forth_init(&vm);

    ForthTables tables;
    memset(&tables, 0, sizeof(tables));

    const char *csource = [source UTF8String];
    int built = forth_compile(&vm, &tables, csource);

    if (built) {
        // applique la ou les tables au moteur CAM (y compris la table
        // Margolus du plan 1 si la règle expédie >PLN1) et bascule le
        // mode d'évolution correspondant.
        cam_apply_forth_tables(&tables, built);

        // reset la grille
        if (self.camState) {
            uint32_t total = self.camState->width * self.camState->height;
            memset(self.camState->plane0_a, 0, total);
            memset(self.camState->plane0_b, 0, total);
            memset(self.camState->plane1_a, 0, total);
            memset(self.camState->plane1_b, 0, total);
            for (uint32_t i = 0; i < total; i++) {
                self.camState->plane0_a[i] = (arc4random_uniform(100) < 20) ? 1 : 0;
            }
        }

        if (self.onRuleCompiled) self.onRuleCompiled();

        if ((built & FORTH_BUILT_MARGOLUS) && (built & FORTH_BUILT_LUT)) {
            _statusLabel.stringValue = @"✅ Compilé (LUT + Margolus) — mode Moore actif.";
        } else if (built & FORTH_BUILT_MARGOLUS) {
            _statusLabel.stringValue = @"✅ Compilé — voisinage de Margolus.";
        } else if ((built & FORTH_BUILT_LUT) &&
                   tables.lut_neighborhood == FORTH_NEIGHBORHOOD_CUSTOM) {
            _statusLabel.stringValue = [NSString stringWithFormat:
                @"✅ Compilé — voisinage personnalisé (%d voisin%s).",
                tables.custom_count, tables.custom_count > 1 ? "s" : ""];
        } else {
            _statusLabel.stringValue = @"✅ Compilé et lancé !";
        }
        _statusLabel.textColor = [NSColor systemGreenColor];
    } else {
        _statusLabel.stringValue = @"❌ Erreur — MAKE-TABLE ou MAKE-TABLE-MARGOLUS non trouvé.";
        _statusLabel.textColor = [NSColor systemRedColor];
    }
}

- (void)showEditor {
    [self.window makeKeyAndOrderFront:nil];
}

@end
