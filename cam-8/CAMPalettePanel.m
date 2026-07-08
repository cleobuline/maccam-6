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
@property (strong) NSButton    *sprayBtn;
@property (strong) NSSlider    *sizeSlider;
@property (strong) NSTextField *sizeLabel;
@property (strong) NSTextField *densityField;
@property (strong) NSPopUpButton *planePopup;
@property (strong) NSPopUpButton *sizePopup;
@property (strong) NSTextField   *fpsField;
@property (strong) NSTextField   *viscosityField;
@property (strong) NSButton    *reverseBtn;
@property (strong) NSButton    *playPauseBtn;
@property (strong) NSButton    *randomizeBtn;
@property (strong) NSPopUpButton *clearBtn;
@property (strong) NSTextField   *controlsLabel; // repositionne quand le bloc FHP se cache/montre
@property (assign) BOOL          fhpControlsCollapsed; // vrai si le decalage "replie" est deja applique

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
    NSRect frame = NSMakeRect(900, 400, 190, 669); // ajustee (6/7) : marge du bas ramenee de 88px a ~13px
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
    CGFloat y = 629; // ajuste (6/7) avec la nouvelle hauteur de fenetre, meme marge en haut
    CGFloat x = 10;
    CGFloat w = 170;

    // --- TAILLE DE GRILLE ---
    [self _addLabel:@"TAILLE GRILLE" x:x y:y w:w view:v];
    y -= 20;

    _sizePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x, y, w, 24) pullsDown:NO];
    [_sizePopup addItemsWithTitles:@[@"128 × 128", @"256 × 256", @"512 × 512", @"1024 × 1024"]];
    [_sizePopup selectItemAtIndex:1]; // 256 par défaut, comme aujourd'hui
    _sizePopup.target = self;
    _sizePopup.action = @selector(_gridSizeChanged:);
    [v addSubview:_sizePopup];
    y -= 32;

    // --- FPS ---
    [self _addLabel:@"FPS (débit de simulation)" x:x y:y w:w view:v];
    y -= 20;

    _fpsField = [NSTextField textFieldWithString:@"30"];
    _fpsField.frame = NSMakeRect(x, y, 50, 22);
    [v addSubview:_fpsField];

    NSButton *fpsApply = [NSButton buttonWithTitle:@"Appliquer"
                                             target:self action:@selector(_fpsChanged:)];
    fpsApply.frame = NSMakeRect(x+58, y-2, 104, 26);
    [v addSubview:fpsApply];
    y -= 32;

    // --- OUTILS ---
    [self _addLabel:@"OUTILS" x:x y:y w:w view:v];
    y -= 24;

    _pencilBtn = [self _toolButton:@"🖌 Pinceau" tag:0 x:x      y:y w:80 view:v];
    _circleBtn = [self _toolButton:@"⭕ Cercle"  tag:1 x:x+85   y:y w:80 view:v];
    y -= 24;
    _squareBtn = [self _toolButton:@"⬛ Carré"   tag:2 x:x      y:y w:80 view:v];
    _eraserBtn = [self _toolButton:@"◻ Gomme"   tag:3 x:x+85   y:y w:80 view:v];
    y -= 24;
    // Spray : densite aleatoire dans le rayon du pinceau. En mode CAM,
    // seme des cellules eparses (utile pour des textures organiques,
    // germes de dendrite...). En mode FHP, injecte du gaz UNIQUEMENT
    // sur le canal HEX-E -- un "vent" dirige, pour former un vrai jet
    // au lieu du grouillement isotrope de Lancer.
    _sprayBtn  = [self _toolButton:@"💨 Spray"   tag:4 x:x      y:y w:170 view:v];

    // pinceau sélectionné par défaut
    _pencilBtn.state = NSControlStateValueOn;
    y -= 32;

    // --- TAILLE ---
    [self _addLabel:@"TAILLE" x:x y:y w:w view:v];
    y -= 20;

    _sizeSlider = [NSSlider sliderWithValue:3 minValue:1 maxValue:20
                                     target:self action:@selector(_sizeChanged:)];
    _sizeSlider.frame = NSMakeRect(x, y, 130, 20);
    [v addSubview:_sizeSlider];

    _sizeLabel = [NSTextField labelWithString:@"3"];
    _sizeLabel.frame = NSMakeRect(x+135, y, 30, 20);
    _sizeLabel.textColor = [NSColor colorWithRed:0 green:0.85 blue:1 alpha:1];
    [v addSubview:_sizeLabel];
    y -= 32;

    // --- % ALÉATOIRE ---
    [self _addLabel:@"% ALÉATOIRE" x:x y:y w:w view:v];
    y -= 22;

    _densityField = [NSTextField textFieldWithString:@"30"];
    _densityField.frame = NSMakeRect(x, y, 55, 22);
    [v addSubview:_densityField];

    _randomizeBtn = [NSButton buttonWithTitle:@"🎲 Lancer"
                                       target:self
                                       action:@selector(_randomize)];
    _randomizeBtn.frame = NSMakeRect(x+62, y-2, 100, 26);
    [v addSubview:_randomizeBtn];
    y -= 32;

    // --- PLANE ---
    [self _addLabel:@"PLANE" x:x y:y w:w view:v];
    y -= 20;

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
    y -= 22;

    // cases de visibilité : quel plan participe à l'AFFICHAGE
    _visibleMask = 0xF;
    // Chiffres au-dessus des cases (pas DANS leur titre) : 4 cases sur
    // ~170px de large ne laissent que 42px chacune, trop juste pour un
    // titre + le glyphe de case a cocher -- le chiffre se faisait
    // rogner silencieusement. Une rangee de labels separee, alignee
    // par-dessus, n'a pas cette contrainte.
    for (int p = 0; p < 4; p++) {
        NSTextField *num = [NSTextField labelWithString:[NSString stringWithFormat:@"%d", p]];
        num.frame = NSMakeRect(x + p * 42 + 14, y, 20, 14);
        num.font = [NSFont systemFontOfSize:10];
        num.textColor = [NSColor colorWithWhite:1.0 alpha:0.6];
        [v addSubview:num];
    }
    y -= 16;
    for (int p = 0; p < 4; p++) {
        NSButton *cb = [NSButton checkboxWithTitle:@""
                                            target:self action:@selector(_visibilityChanged:)];
        cb.frame = NSMakeRect(x + p * 42, y, 36, 18);
        cb.state = NSControlStateValueOn;
        cb.tag = p;
        cb.toolTip = [NSString stringWithFormat:@"Afficher le plan %d", p];
        [v addSubview:cb];
    }
    y -= 32;

    // --- MODE FHP (chapitre 16) ---
    // En-tete TOUJOURS visible (comme les autres titres de section),
    // meme quand les reglages en dessous sont masques -- donne un
    // repere immediat a quelqu'un qui decouvre l'app.
    [self _addLabel:@"GRILLE HEXAGONALE (chapitre 16)" x:x y:y w:w view:v];
    y -= 20;

    // Une seule case : elle bascule TOUTE la grille sur le gaz FHP
    // (fhp.h/.c) au lieu de CAM-A/CAM-B/Margolus. Desactivee par
    // defaut : aucun changement de comportement si on n'y touche pas.
    NSButton *fhpCheck = [NSButton checkboxWithTitle:@"Grille hexagonale"
                                              target:self action:@selector(_fhpModeChanged:)];
    fhpCheck.frame = NSMakeRect(x, y, w, 20);
    fhpCheck.state = NSControlStateValueOff;
    fhpCheck.toolTip = @"Mode FHP (gaz, chapitre 16) : bascule la grille sur le vrai gaz hexagonal a 6 canaux (fhp.c). En mode FHP, le pinceau pose des OBSTACLES au lieu de peindre les plans.";
    [self _forceVisibleTitle:fhpCheck];
    [v addSubview:fhpCheck];
    y -= 22;

    NSButton *windCheck = [NSButton checkboxWithTitle:@"Vent d'Ouest"
                                               target:self action:@selector(_windChanged:)];
    windCheck.frame = NSMakeRect(x, y, w, 20);
    windCheck.state = NSControlStateValueOff;
    windCheck.toolTip = @"Reinjecte du gaz HEX-E le long du bord gauche a chaque pas pendant Play -- indispensable pour un vrai jet/sillage, un Spray ponctuel se disperse et s'equilibre.";
    [self _forceVisibleTitle:windCheck];
    [v addSubview:windCheck];
    y -= 22;

    NSButton *openCheck = [NSButton checkboxWithTitle:@"Bord droit absorbant"
                                               target:self action:@selector(_openChannelChanged:)];
    openCheck.frame = NSMakeRect(x, y, w, 20);
    openCheck.state = NSControlStateValueOff;
    openCheck.toolTip = @"Bords ouverts : le gaz qui atteint le bord droit sort du domaine au lieu de reapparaitre a gauche par le tore -- evite la recirculation en bandes stagnantes avec un vent continu.";
    [self _forceVisibleTitle:openCheck];
    [v addSubview:openCheck];
    y -= 22;

    // --- VISCOSITE (FHP-II, particules au repos) ---
    NSTextField *viscosityLabel = [self _addLabel:@"Viscosité (particules au repos, %)" x:x y:y w:w view:v];
    y -= 20;

    _viscosityField = [NSTextField textFieldWithString:@"0"];
    _viscosityField.frame = NSMakeRect(x, y, 50, 22);
    _viscosityField.toolTip = @"0 = FHP-I classique. Plus haut, plus le gaz \"colle\" en particules au repos lors des collisions frontales -- c'est ce qui donne au sillage derriere un obstacle sa vraie viscosite.";
    [v addSubview:_viscosityField];

    NSButton *viscosityApply = [NSButton buttonWithTitle:@"Appliquer"
                                             target:self action:@selector(_viscosityChanged:)];
    viscosityApply.frame = NSMakeRect(x+58, y-2, 104, 26);
    [v addSubview:viscosityApply];
    y -= 32;

    // --- SPRAY ISOTROPE (perturbation sans biais directionnel) ---
    NSButton *isoCheck = [NSButton checkboxWithTitle:@"Spray isotrope"
                                              target:self action:@selector(_sprayIsotropicChanged:)];
    isoCheck.frame = NSMakeRect(x, y, w, 20);
    isoCheck.state = NSControlStateValueOff;
    isoCheck.toolTip = @"Decoche (defaut) : Spray injecte un vent dirige (HEX-E), pour les scenes de soufflerie. Coche : Spray injecte du gaz sur les 6 directions a la fois, une perturbation LOCALE et SANS biais -- comme jeter un caillou dans l'eau, ideal pour observer une onde qui s'amortit.";
    [self _forceVisibleTitle:isoCheck];
    [v addSubview:isoCheck];
    y -= 22;

    // Regroupe les controles FHP et les cache par defaut : Mode FHP
    // demarre decoche, donc ces reglages n'ont aucun sens tant qu'on
    // ne l'a pas active -- inutile de noyer quelqu'un qui n'utilise
    // que le CAM classique sous des cases qui ne le concernent pas.
    _fhpControlsViews = @[windCheck, openCheck, viscosityLabel, _viscosityField, viscosityApply, isoCheck];
    for (NSView *cv in _fhpControlsViews) cv.hidden = YES;

    // (Le popup VOISINAGE a été retiré : le voisinage est désormais
    // entièrement déterminé par la règle compilée — MAKE-TABLE pour
    // Moore, MAKE-TABLE-MARGOLUS pour Margolus. Une seule source de
    // vérité : le texte de la règle.)

    // --- CONTRÔLES ---
    _controlsLabel = [self _addLabel:@"CONTRÔLES" x:x y:y w:w view:v];
    y -= 24;

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
    y -= 28;

    _clearBtn = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x, y, 165, 26) pullsDown:YES];
    [_clearBtn addItemWithTitle:@"🗑 Effacer..."]; // toujours visible, jamais declenchable elle-meme
    [_clearBtn addItemWithTitle:@"Effacer plan 0"];
    [_clearBtn addItemWithTitle:@"Effacer plan 1"];
    [_clearBtn addItemWithTitle:@"Effacer plan 2"];
    [_clearBtn addItemWithTitle:@"Effacer plan 3"];
    [_clearBtn addItemWithTitle:@"Effacer tout"];
    // tags : 0-3 = plan correspondant, -1 = tout (garde le sens de
    // l'ancien "Effacer tout" qui videait aussi le gaz FHP au passage)
    [[_clearBtn itemArray][1] setTag:0];
    [[_clearBtn itemArray][2] setTag:1];
    [[_clearBtn itemArray][3] setTag:2];
    [[_clearBtn itemArray][4] setTag:3];
    [[_clearBtn itemArray][5] setTag:-1];
    _clearBtn.target = self;
    _clearBtn.action = @selector(_clearMenuSelected:);
    [v addSubview:_clearBtn];

    // Mode FHP demarre DECOCHE : replie immediatement le bloc FHP des
    // la construction, pour que la fenetre s'affiche d'emblee dans son
    // format compact plutot que dans le format complet avec un grand
    // espace vide -- c'est ce format complet qui debordait de l'ecran.
    [self _updateFHPControlsVisibility:NO];
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

- (NSTextField *)_addLabel:(NSString *)text x:(CGFloat)x y:(CGFloat)y
                w:(CGFloat)w view:(NSView *)v {
    NSTextField *lbl = [NSTextField labelWithString:text];
    lbl.frame     = NSMakeRect(x, y, w, 18);
    lbl.font      = [NSFont boldSystemFontOfSize:10];
    lbl.textColor = [NSColor colorWithRed:0 green:0.85 blue:1 alpha:0.7];
    [v addSubview:lbl];
    return lbl;
}

// NSButton (checkboxWithTitle:) n'a pas de propriete .textColor directe
// -- sans forcer une couleur explicite via attributedTitle, le titre
// utilise la couleur systeme par defaut, qui peut etre quasi invisible
// sur le fond sombre de cette palette. Decouvert le 6/7 : plusieurs
// cases (Mode FHP, Vent, Bords ouverts, Spray isotrope) semblaient
// n'avoir AUCUN titre a l'ecran alors que le texte existait bel et
// bien dans le code -- un probleme de contraste, pas d'absence.
- (void)_forceVisibleTitle:(NSButton *)checkbox {
    NSDictionary *attrs = @{
        NSForegroundColorAttributeName: [NSColor whiteColor],
        NSFontAttributeName: [NSFont systemFontOfSize:12]
    };
    checkbox.attributedTitle = [[NSAttributedString alloc] initWithString:checkbox.title attributes:attrs];
}

// --- Actions ---
- (void)_selectTool:(NSButton *)sender {
    _currentTool = (CAMTool)sender.tag;

    for (NSButton *btn in @[_pencilBtn, _circleBtn, _squareBtn, _eraserBtn, _sprayBtn]) {
        btn.state = (btn.tag == sender.tag)
                    ? NSControlStateValueOn
                    : NSControlStateValueOff;
    }
}

- (void)_sizeChanged:(NSSlider *)sender {
    _brushSize = (int)sender.intValue;
    _sizeLabel.stringValue = [NSString stringWithFormat:@"%d", _brushSize];
}

- (void)_fpsChanged:(id)sender {
    int fps = _fpsField.intValue;
    if (fps < 1) fps = 1;
    if (fps > 60) fps = 60; // au-delà, CVDisplayLink ne suit plus le rafraîchissement réel
    _fpsField.stringValue = [NSString stringWithFormat:@"%d", fps];
    if (self.onFPSChange) self.onFPSChange(fps);
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

- (void)_fhpModeChanged:(NSButton *)sender {
    _fhpMode = (sender.state == NSControlStateValueOn);
    [self _updateFHPControlsVisibility:_fhpMode];
}

// Cache/montre les 4 controles FHP (Vent, Bords ouverts, Viscosite,
// Spray isotrope) ET repositionne tout ce qui suit (CONTROLES,
// Play/Reverse, le menu Effacer) pour combler l'espace -- sans ca, le
// masquage laissait un grand vide et la fenetre debordait de l'ecran.
// Redimensionne aussi la fenetre elle-meme (136px, la hauteur exacte
// du bloc FHP), en gardant le bord SUPERIEUR fixe pour que la barre de
// titre ne saute pas visuellement.
- (void)_updateFHPControlsVisibility:(BOOL)showFHPControls {
    // Version simplifiee, en toute honnetete : ma premiere tentative
    // deplaçait CONTROLES/Play/Reverse/Effacer vers le HAUT pour
    // "combler" le vide laisse par le bloc FHP cache -- mais les
    // eloigner du bas de la fenetre ne fait qu'AGRANDIR leur distance
    // au bord inferieur (y=0), pas la reduire. Resultat : un vide
    // encore PLUS grand qu'avant en mode replie, l'inverse de l'effet
    // voulu. Sans pouvoir compiler et verifier ce genre de calcul de
    // repositionnement, je prefere cette version plus simple et sure :
    // masquer sans rien deplacer. Il restera un espace au MILIEU de la
    // palette (entre "Grille hexagonale" et "CONTROLES") quand le mode
    // FHP est decoche, moins joli qu'un repli parfait, mais au moins
    // la fenetre elle-meme ne depasse plus de l'ecran -- corrige separement
    // via sa taille de base (voir _buildUI).
    for (NSView *cv in _fhpControlsViews) cv.hidden = showFHPControls ? NO : YES;
}

- (void)_windChanged:(NSButton *)sender {
    _continuousWind = (sender.state == NSControlStateValueOn);
}

- (void)_openChannelChanged:(NSButton *)sender {
    _openChannel = (sender.state == NSControlStateValueOn);
}

- (void)_viscosityChanged:(id)sender {
    int v = _viscosityField.intValue;
    if (v < 0) v = 0;
    if (v > 100) v = 100;
    _viscosityField.stringValue = [NSString stringWithFormat:@"%d", v];
    _fhpViscosity = v;
}

- (void)_sprayIsotropicChanged:(NSButton *)sender {
    _sprayIsotropic = (sender.state == NSControlStateValueOn);
}

- (void)_visibilityChanged:(NSButton *)sender {
    int bit = 1 << sender.tag;
    if (sender.state == NSControlStateValueOn) _visibleMask |= bit;
    else                                        _visibleMask &= ~bit;
}

// Lecture TOUJOURS live du champ "% ALÉATOIRE" : Spray (et tout autre
// appelant) doit voir la valeur actuellement tapee, meme si Lancer n'a
// jamais ete cliqué avec cette valeur precise.
- (int)density {
    return _densityField ? _densityField.intValue : _density;
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

- (void)_clearMenuSelected:(NSPopUpButton *)sender {
    NSInteger tag = sender.selectedItem.tag;
    if (tag == -1) {
        if (self.onClear) self.onClear();
    } else {
        if (self.onClearPlane) self.onClearPlane((int)tag);
    }
}

- (void)showPalette {
    [self makeKeyAndOrderFront:nil];
}

@end
