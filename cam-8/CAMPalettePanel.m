//
//  CAMPalettePanel.m
//  cam-8
//

#import "CAMPalettePanel.h"

@interface CAMPalettePanel ()

@property (strong) NSButton    *pencilBtn;
@property (strong) NSButton    *circleBtn;
@property (strong) NSButton    *squareBtn;
@property (strong) NSButton    *eraserBtn;
@property (strong) NSSlider    *sizeSlider;
@property (strong) NSTextField *sizeLabel;
@property (strong) NSTextField *densityField;
@property (strong) NSPopUpButton *planePopup;
@property (strong) NSPopUpButton *sizePopup;
@property (strong) NSButton    *reverseBtn;
@property (strong) NSButton    *playPauseBtn;
@property (strong) NSButton    *randomizeBtn;
@property (strong) NSButton    *clearBtn;

@end

@implementation CAMPalettePanel

+ (instancetype)sharedPalette {
    static CAMPalettePanel *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[CAMPalettePanel alloc] init];
    });
    return instance;
}

- (instancetype)init {
    NSRect frame = NSMakeRect(900, 400, 190, 486);
    self = [super initWithContentRect:frame
                            styleMask:NSWindowStyleMaskTitled |
                                      NSWindowStyleMaskClosable |
                                      NSWindowStyleMaskUtilityWindow
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (self) {
        self.title = @"Palette";
        self.floatingPanel = YES;
        self.becomesKeyOnlyIfNeeded = YES;
        self.backgroundColor = [NSColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];

        _currentTool  = CAMToolPencil;
        _brushSize    = 3;
        _density      = 30;
        _currentPlane = 0;
        _isRunning    = NO; // pause au départ — synchronisé avec Document

        [self _buildUI];
    }
    return self;
}

- (void)_buildUI {
    NSView *v = self.contentView;
    CGFloat y = 446;
    CGFloat x = 10;
    CGFloat w = 170;

    // --- TAILLE DE GRILLE ---
    [self _addLabel:@"TAILLE GRILLE" x:x y:y w:w view:v];
    y -= 24;

    _sizePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x, y, w, 24) pullsDown:NO];
    [_sizePopup addItemsWithTitles:@[@"128 × 128", @"256 × 256", @"512 × 512", @"1024 × 1024"]];
    [_sizePopup selectItemAtIndex:1]; // 256 par défaut, comme aujourd'hui
    _sizePopup.target = self;
    _sizePopup.action = @selector(_gridSizeChanged:);
    [v addSubview:_sizePopup];
    y -= 38;

    // --- OUTILS ---
    [self _addLabel:@"OUTILS" x:x y:y w:w view:v];
    y -= 28;

    _pencilBtn = [self _toolButton:@"🖌 Pinceau" tag:0 x:x      y:y w:80 view:v];
    _circleBtn = [self _toolButton:@"⭕ Cercle"  tag:1 x:x+85   y:y w:80 view:v];
    y -= 28;
    _squareBtn = [self _toolButton:@"⬛ Carré"   tag:2 x:x      y:y w:80 view:v];
    _eraserBtn = [self _toolButton:@"◻ Gomme"   tag:3 x:x+85   y:y w:80 view:v];

    // pinceau sélectionné par défaut
    _pencilBtn.state = NSControlStateValueOn;
    y -= 38;

    // --- TAILLE ---
    [self _addLabel:@"TAILLE" x:x y:y w:w view:v];
    y -= 24;

    _sizeSlider = [NSSlider sliderWithValue:3 minValue:1 maxValue:20
                                     target:self action:@selector(_sizeChanged:)];
    _sizeSlider.frame = NSMakeRect(x, y, 130, 20);
    [v addSubview:_sizeSlider];

    _sizeLabel = [NSTextField labelWithString:@"3"];
    _sizeLabel.frame = NSMakeRect(x+135, y, 30, 20);
    _sizeLabel.textColor = [NSColor colorWithRed:0 green:0.85 blue:1 alpha:1];
    [v addSubview:_sizeLabel];
    y -= 38;

    // --- % ALÉATOIRE ---
    [self _addLabel:@"% ALÉATOIRE" x:x y:y w:w view:v];
    y -= 26;

    _densityField = [NSTextField textFieldWithString:@"30"];
    _densityField.frame = NSMakeRect(x, y, 55, 22);
    [v addSubview:_densityField];

    _randomizeBtn = [NSButton buttonWithTitle:@"🎲 Lancer"
                                       target:self
                                       action:@selector(_randomize)];
    _randomizeBtn.frame = NSMakeRect(x+62, y-2, 100, 26);
    [v addSubview:_randomizeBtn];
    y -= 38;

    // --- PLANE ---
    [self _addLabel:@"PLANE" x:x y:y w:w view:v];
    y -= 24;

    _planePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x, y, w, 24) pullsDown:NO];
    [_planePopup addItemsWithTitles:@[
        @"Plane 0 — A vivant (blanc)",
        @"Plane 1 — A écho (cyan)",
        @"Plane 2 — B (vert)",
        @"Plane 3 — B (orange)"
    ]];
    _planePopup.target = self;
    _planePopup.action = @selector(_planeChanged:);
    [v addSubview:_planePopup];
    y -= 26;

    // cases de visibilité : quel plan participe à l'AFFICHAGE
    _visibleMask = 0xF;
    for (int p = 0; p < 4; p++) {
        NSButton *cb = [NSButton checkboxWithTitle:[NSString stringWithFormat:@"%d", p]
                                            target:self action:@selector(_visibilityChanged:)];
        cb.frame = NSMakeRect(x + p * 42, y, 40, 18);
        cb.state = NSControlStateValueOn;
        cb.tag = p;
        cb.toolTip = [NSString stringWithFormat:@"Afficher le plan %d", p];
        [v addSubview:cb];
    }
    y -= 38;

    // (Le popup VOISINAGE a été retiré : le voisinage est désormais
    // entièrement déterminé par la règle compilée — MAKE-TABLE pour
    // Moore, MAKE-TABLE-MARGOLUS pour Margolus. Une seule source de
    // vérité : le texte de la règle.)

    // --- CONTRÔLES ---
    [self _addLabel:@"CONTRÔLES" x:x y:y w:w view:v];
    y -= 28;

    _playPauseBtn = [NSButton buttonWithTitle:(_isRunning ? @"⏸ Pause" : @"▶️ Play")
                                       target:self
                                       action:@selector(_playPause)];
    _playPauseBtn.frame = NSMakeRect(x, y, 80, 26);
    [v addSubview:_playPauseBtn];

    _reverseBtn = [NSButton buttonWithTitle:@"⏪ Reverse"
                                     target:self
                                     action:@selector(_reverse)];
    _reverseBtn.frame = NSMakeRect(x+85, y, 80, 26);
    [v addSubview:_reverseBtn];
    y -= 32;

    _clearBtn = [NSButton buttonWithTitle:@"🗑 Effacer tout"
                                   target:self
                                   action:@selector(_clear)];
    _clearBtn.frame = NSMakeRect(x, y, 165, 26);
    [v addSubview:_clearBtn];
}

- (NSButton *)_toolButton:(NSString *)title tag:(NSInteger)tag
                        x:(CGFloat)x y:(CGFloat)y w:(CGFloat)w view:(NSView *)v {
    NSButton *btn = [[NSButton alloc] initWithFrame:NSMakeRect(x, y, w, 24)];
    btn.title      = title;
    btn.target     = self;
    btn.action     = @selector(_selectTool:);
    btn.tag        = tag;
    btn.buttonType = NSPushOnPushOffButton;
    btn.bezelStyle = NSBezelStyleRounded;
    btn.state      = NSControlStateValueOff;
    [v addSubview:btn];
    return btn;
}

- (void)_addLabel:(NSString *)text x:(CGFloat)x y:(CGFloat)y
                w:(CGFloat)w view:(NSView *)v {
    NSTextField *lbl = [NSTextField labelWithString:text];
    lbl.frame     = NSMakeRect(x, y, w, 18);
    lbl.font      = [NSFont boldSystemFontOfSize:10];
    lbl.textColor = [NSColor colorWithRed:0 green:0.85 blue:1 alpha:0.7];
    [v addSubview:lbl];
}

// --- Actions ---
- (void)_selectTool:(NSButton *)sender {
    _currentTool = (CAMTool)sender.tag;

    for (NSButton *btn in @[_pencilBtn, _circleBtn, _squareBtn, _eraserBtn]) {
        btn.state = (btn.tag == sender.tag)
                    ? NSControlStateValueOn
                    : NSControlStateValueOff;
    }
}

- (void)_sizeChanged:(NSSlider *)sender {
    _brushSize = (int)sender.intValue;
    _sizeLabel.stringValue = [NSString stringWithFormat:@"%d", _brushSize];
}

- (void)_planeChanged:(NSPopUpButton *)sender {
    _currentPlane = (int)sender.indexOfSelectedItem;
}

- (void)_gridSizeChanged:(NSPopUpButton *)sender {
    static const int sizes[4] = {128, 256, 512, 1024};
    int newSize = sizes[sender.indexOfSelectedItem];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Changer la taille de la grille ?";
    alert.informativeText = [NSString stringWithFormat:
        @"La grille sera recréée à %d × %d. Comme \"Effacer tout\", "
        @"ceci efface le contenu des QUATRE plans — mais en plus, "
        @"impossible à annuler par Reverse.", newSize, newSize];
    [alert addButtonWithTitle:@"Recréer la grille"];
    [alert addButtonWithTitle:@"Annuler"];
    alert.buttons[1].keyEquivalent = @"\033"; // Échap = Annuler, par sécurité

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        if (self.onSizeChange) self.onSizeChange(newSize);
    } else {
        // restaure la sélection précédente dans le popup
        int cur = 1;
        switch (self.camState ? (int)self.camState->size : 256) {
            case 128: cur = 0; break; case 256: cur = 1; break;
            case 512: cur = 2; break; case 1024: cur = 3; break;
        }
        [sender selectItemAtIndex:cur];
    }
}

- (void)_visibilityChanged:(NSButton *)sender {
    int bit = 1 << sender.tag;
    if (sender.state == NSControlStateValueOn) _visibleMask |= bit;
    else                                        _visibleMask &= ~bit;
}

- (void)_randomize {
    _density = _densityField.intValue;
    if (self.onRandomize) self.onRandomize(_density);
}

- (void)_reverse {
    if (self.onReverse) self.onReverse();
}

- (void)_playPause {
    _isRunning = !_isRunning;
    _playPauseBtn.title = _isRunning ? @"⏸ Pause" : @"▶️ Play";
    if (self.onPlayPause) self.onPlayPause(_isRunning);
}

// Setter custom : permet à Document.m d'imposer l'état (ex: pause au
// lancement) tout en gardant le bouton synchronisé visuellement.
- (void)setIsRunning:(BOOL)isRunning {
    _isRunning = isRunning;
    _playPauseBtn.title = _isRunning ? @"⏸ Pause" : @"▶️ Play";
}

- (void)_clear {
    if (self.onClear) self.onClear();
}

- (void)showPalette {
    [self makeKeyAndOrderFront:nil];
}

@end
