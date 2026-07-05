#import "Document.h"
#import "CAMView.h"
#include "cam_core.h"
#import "CAMPalettePanel.h"
#import "CAMEditorWindowController.h"
#include "fph.h"
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>

// --- Règles ---
static const char *RULE_TIME_TUNNEL =
    ": TIME-TUNNEL\n"
    "  CENTER NORTH SOUTH WEST EAST + + + +\n"
    "  { 0 1 1 1 1 0 }\n"
    "  CENTER' XOR ;\n\n"
    "MAKE-TABLE TIME-TUNNEL";

@interface Document () {
    CAMState *_cam;
    CAMView  *_camView;
    CVDisplayLinkRef _displayLink;
    CFTimeInterval _lastFrameTime;
    BOOL _timeReversed; // YES = la simulation recule (chapitre 14)
    CFTimeInterval _frameInterval; // 1.0/fps — réglable via la palette
    NSString *_pendingRuleSource; // règle lue depuis un fichier avant que la fenêtre existe
    NSString *_currentRuleSource; // dernière règle compilée avec succès, pour survivre à un changement de taille
    FHPState *_fhp; // sous-systeme gaz FHP (chapitre 16), independant de _cam
    NSTextField *_videoScaleField; // "auto" ou une valeur numerique (0.5, 2, 3...)
}
@property (nonatomic, assign) BOOL isRunning;@end

@implementation Document

static CVReturn DisplayLinkCallback(CVDisplayLinkRef displayLink, const CVTimeStamp *inNow, const CVTimeStamp *inOutputTime, CVOptionFlags flagsIn, CVOptionFlags *flagsOut, void *displayLinkContext) {
    Document *document = (__bridge Document *)displayLinkContext;
    [document _displayLinkTick];
    return kCVReturnSuccess;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cam = cam_create(CAM_SIZE_256);
        _isRunning = NO; // en pause au départ — l'utilisateur décide quand lancer
        _frameInterval = 1.0 / 30.0; // 30 fps par défaut, comme avant
        cam_set_rule(RULE_TIME_TUNNEL);
        _fhp = fhp_create(_cam->width, _cam->height); // toujours cree, mais inerte tant que fhpMode est OFF
    }
    return self;
}

- (void)dealloc {
    if (_displayLink) {
        CVDisplayLinkStop(_displayLink);
        CVDisplayLinkRelease(_displayLink);
    }
    if (_cam) cam_destroy(_cam);
    if (_fhp) fhp_destroy(_fhp);
}

- (NSString *)windowNibName { return @"Document"; }

- (void)windowControllerDidLoadNib:(NSWindowController *)windowController {
    [super windowControllerDidLoadNib:windowController];

    NSView *contentView = windowController.window.contentView;
    NSRect frame = contentView.bounds;

    // Le nib par défaut du template "document-based app" contient un
    // placeholder ("Put your document contents here" ou équivalent).
    // On le retire avant de construire notre propre UI, sinon il reste
    // visible en dessous dès que la fenêtre est plus grande que le
    // splitView initial.
    for (NSView *defaultSubview in [contentView.subviews copy]) {
        [defaultSubview removeFromSuperview];
    }

    NSSplitView *splitView = [[NSSplitView alloc] initWithFrame:frame];
    splitView.vertical = YES;
    splitView.dividerStyle = NSSplitViewDividerStyleThin;
    splitView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // Panneau gauche : Simulation
    NSView *leftContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width * 0.65, frame.size.height)];
    leftContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _camView = [[CAMView alloc] initWithFrame:leftContainer.bounds];
    _camView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _camView.camState = _cam;
    _camView.fhpState = _fhp;
    [leftContainer addSubview:_camView];

    // Panneau droit : Éditeur
    NSView *editorContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width * 0.35, frame.size.height)];
    editorContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // Deux boutons-icônes compacts, ancrés en bas à gauche. Largeur FIXE
    // (NSViewMaxXMargin, pas WidthSizable) : ils ne s'étirent jamais, donc
    // ne peuvent plus se chevaucher quand le panneau change de largeur —
    // c'est la zone de texte au-dessus qui absorbe toute l'élasticité.
    // Icônes : images template système (pas d'émoji dans les titres, ça
    // tronque en "…" sur certains systèmes) — vectorielles, adaptées au
    // mode sombre, disponibles depuis toujours.
    NSButton *compileBtn = [NSButton buttonWithImage:[NSImage imageNamed:NSImageNameActionTemplate]
                                              target:self
                                              action:@selector(compileRule:)];
    compileBtn.frame = NSMakeRect(10, 10, 44, 30);
    compileBtn.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    compileBtn.imagePosition = NSImageOnly;
    compileBtn.toolTip = @"Compiler la règle";
    [editorContainer addSubview:compileBtn];

    NSButton *exportBtn = [NSButton buttonWithTitle:@"🎬"
                                             target:self
                                             action:@selector(exportVideo:)];
    // 56 px : le bezel arrondi mange ~14 px de marge interne de chaque
    // côté, et à 44 px le clap ne "rentrait" plus → NSButton tronquait
    // en "…". On interdit aussi explicitement la troncature (clipping).
    exportBtn.frame = NSMakeRect(60, 10, 56, 30);
    exportBtn.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    exportBtn.font = [NSFont systemFontOfSize:16];
    [(NSButtonCell *)exportBtn.cell setLineBreakMode:NSLineBreakByClipping];
    exportBtn.toolTip = @"Exporter en vidéo…";
    [editorContainer addSubview:exportBtn];

    // Champ d'échelle vidéo, réglable : "auto" (défaut, vise ~768px de
    // côté comme avant) ou une valeur numérique explicite (0.5, 1, 2,
    // 3...) — multiplie la taille NATIVE de la grille, pas la taille
    // d'écran. 0.5 = video a moitie resolution, 2 = double, etc.
    _videoScaleField = [NSTextField textFieldWithString:@"auto"];
    _videoScaleField.frame = NSMakeRect(124, 14, 60, 22);
    _videoScaleField.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    _videoScaleField.alignment = NSTextAlignmentCenter;
    _videoScaleField.toolTip = @"Échelle vidéo : \"auto\" (~768px), ou une valeur comme 0.5, 1, 2, 3 — multiplie la taille native de la grille.";
    [editorContainer addSubview:_videoScaleField];

    // Texte — scrollableTextView configure correctement l'élasticité
    // (textContainer qui suit la largeur, verticallyResizable, scrollers, etc.)
    // au lieu de tout assembler à la main comme avant.
    NSScrollView *sv = [NSTextView scrollableTextView];
    sv.frame = NSMakeRect(10, 50,
                           editorContainer.bounds.size.width - 20,
                           editorContainer.bounds.size.height - 60);
    sv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    sv.hasVerticalScroller = YES;
    sv.hasHorizontalScroller = NO;
    sv.borderType = NSNoBorder;

    NSString *initialSource = _pendingRuleSource ?: [NSString stringWithUTF8String:RULE_TIME_TUNNEL];

    NSTextView *tv = (NSTextView *)sv.documentView;
    tv.font = [NSFont userFixedPitchFontOfSize:13.0];
    tv.string = initialSource;
    tv.minSize = NSMakeSize(0.0, sv.contentSize.height);
    tv.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    tv.verticallyResizable = YES;
    tv.horizontallyResizable = NO;
    tv.autoresizingMask = NSViewWidthSizable;
    tv.textContainer.widthTracksTextView = YES;
    tv.textContainer.containerSize = NSMakeSize(sv.contentSize.width, FLT_MAX);

    [editorContainer addSubview:sv];
    self.ruleTextView = tv;

    // Si un fichier a été chargé avant que la fenêtre existe, le texte
    // affiche déjà sa règle (ci-dessus). On ne touche PAS à la LUT du
    // moteur CAM ici — elle ne change que quand l'utilisateur clique
    // "Compiler la Règle".
    _pendingRuleSource = nil;

    [splitView addSubview:leftContainer];
    [splitView addSubview:editorContainer];
    [contentView addSubview:splitView];

    // Câblage Palette
    CAMPalettePanel *palette = [CAMPalettePanel sharedPalette];
    __weak Document *weakSelf = self;
    palette.onPlayPause = ^(BOOL r) { weakSelf.isRunning = r; };
    palette.onRandomize = ^(int d) { [weakSelf _randomizePlanes:d]; };
    palette.onClear = ^(void) { [weakSelf _clearPlanes]; };
    // (Plus de câblage "voisinage" : le mode Moore/Margolus est déterminé
    // par la règle compilée — MAKE-TABLE ou MAKE-TABLE-MARGOLUS.)
    palette.onSizeChange = ^(int newSize) {
        [weakSelf _recreateGridAtSize:newSize];
    };
    palette.onFPSChange = ^(int fps) {
        Document *strongSelf = weakSelf;
        if (strongSelf) strongSelf->_frameInterval = 1.0 / (double)fps;
    };
    palette.onReverse = ^(void) {
        Document *strongSelf = weakSelf;
        if (!strongSelf || !strongSelf->_cam) return;

        if (cam_can_reverse()) {
            // Mode Margolus inversible (chapitre 14) : le bouton inverse la
            // FLÈCHE DU TEMPS — la simulation recule tant qu'on ne rappuie
            // pas. La grille n'est pas touchée ici : c'est le tick qui
            // choisit cam_step ou cam_step_back.
            strongSelf->_timeReversed = !strongSelf->_timeReversed;
        } else {
            // Mode LUT (règles du second ordre, ex. TIME-TUNNEL) : échanger
            // présent (plan 0) et passé (plan 1) inverse le temps.
            uint8_t *tmp = strongSelf->_cam->plane0_a;
            strongSelf->_cam->plane0_a = strongSelf->_cam->plane1_a;
            strongSelf->_cam->plane1_a = tmp;
            [strongSelf->_camView renderFrame];
        }
    };
    [palette showPalette];
    // Dans Document.m

    _camView.palette = palette; // <--- AJOUTER CETTE LIGNE
    palette.camState = _cam;
    palette.isRunning = self.isRunning; // synchronise le bouton avec l'état pause du document
    // ... le reste de ton code ...
    // Démarrage
    [self _randomizePlanes:50];
    CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    CVDisplayLinkSetOutputCallback(_displayLink, &DisplayLinkCallback, (__bridge void *)self);
    CVDisplayLinkStart(_displayLink);
}


// Recrée entièrement la grille à une nouvelle taille (menu TAILLE de la
// palette). Toujours destructif sur le contenu — c'est le prix pour
// changer une dimension câblée dans CAMState — mais on réapplique la
// dernière règle compilée avec succès, pour ne pas repartir sur
// TIME-TUNNEL par défaut à chaque changement.
- (void)_recreateGridAtSize:(int)newSize {
    CAMGridSize size;
    switch (newSize) {
        case 128:  size = CAM_SIZE_128;  break;
        case 512:  size = CAM_SIZE_512;  break;
        case 1024: size = CAM_SIZE_1024; break;
        default:   size = CAM_SIZE_256;  break;
    }
    if (_cam && _cam->size == size) return; // déjà à cette taille

    BOOL wasRunning = self.isRunning;
    self.isRunning = NO;
    _timeReversed = NO;

    CAMState *old = _cam;
    CAMState *fresh = cam_create(size);
    if (!fresh) { NSBeep(); return; } // grille trop grande pour la mémoire : on garde l'ancienne

    _cam = fresh;
    cam_destroy(old);

    if (_fhp) fhp_destroy(_fhp);
    _fhp = fhp_create(_cam->width, _cam->height);

    if (_currentRuleSource) cam_set_rule([_currentRuleSource UTF8String]);
    else cam_set_rule(RULE_TIME_TUNNEL);

    _camView.camState = _cam;
    _camView.fhpState = _fhp;
    [CAMPalettePanel sharedPalette].camState = _cam;
    [CAMEditorWindowController sharedEditor].camState = _cam;
    [_camView renderFrame];

    self.isRunning = wasRunning;
}

- (void)_displayLinkTick {
    if (CACurrentMediaTime() - _lastFrameTime < _frameInterval) return;
    _lastFrameTime = CACurrentMediaTime();
    dispatch_async(dispatch_get_main_queue(), ^{
        CAMPalettePanel *pal = [CAMPalettePanel sharedPalette];
        BOOL fhpOn = pal.fhpMode;
        if (self.isRunning) {
            if (fhpOn && self->_fhp) {
                self->_fhp->open_right_edge = pal.openChannel;
                if (pal.continuousWind) {
                    // Reinjection du gaz HEX-E le long du bord gauche, A
                    // CHAQUE pas -- exactement la methode qui a produit
                    // un vrai sillage dans les tests hors-app (fhp_wake).
                    // Un Spray manuel ponctuel ne peut pas reproduire ca :
                    // sans reinjection continue, tout gaz injecte se
                    // disperse et s'equilibre au lieu de former un flux.
                    int density = pal.density;
                    uint32_t H = self->_fhp->height;
                    for (uint32_t row = 0; row < H; row++) {
                        if ((int)arc4random_uniform(100) < density) {
                            self->_fhp->dir_a[FHP_DIR_E][row * self->_fhp->width + 0] = 1;
                        }
                    }
                }
                fhp_step(self->_fhp);
            } else if (self->_timeReversed && cam_can_reverse()) {
                cam_step_back(self->_cam);
            } else {
                cam_step(self->_cam);
            }
        }
        [self->_camView renderFrame];
    });
}

- (IBAction)compileRule:(id)sender {
    _timeReversed = NO; // nouvelle règle : le temps repart vers l'avant
    _currentRuleSource = [self.ruleTextView.string copy];
    cam_set_rule([_currentRuleSource UTF8String]);
}

#pragma mark - Export vidéo

- (IBAction)exportVideo:(id)sender {
    if (!_cam) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Exporter en vidéo";
    alert.informativeText = @"Durée de l'export, en secondes (la simulation à l'écran n'est pas affectée) :";

    NSTextField *secondsField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 60, 24)];
    secondsField.stringValue = @"10";
    secondsField.alignment = NSTextAlignmentCenter;
    alert.accessoryView = secondsField;

    [alert addButtonWithTitle:@"Exporter…"];
    [alert addButtonWithTitle:@"Annuler"];

    NSModalResponse choice = [alert runModal];
    if (choice != NSAlertFirstButtonReturn) return;

    NSInteger seconds = secondsField.integerValue;
    if (seconds <= 0) seconds = 1;
    if (seconds > 600) seconds = 600; // garde-fou : 10 min max

    NSSavePanel *savePanel = [NSSavePanel savePanel];
    savePanel.allowedFileTypes = @[@"mp4"];
    savePanel.nameFieldStringValue = @"cam8-export.mp4";
    savePanel.canCreateDirectories = YES;

    __weak Document *weakSelf = self;
    [savePanel beginSheetModalForWindow:self.windowForSheet
                       completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;
        [weakSelf _exportVideoDurationSeconds:seconds toURL:savePanel.URL];
    }];
}

// Exporte sur un CLONE de la grille courante — la simulation affichée à
// l'écran n'est jamais modifiée par l'export, quelle que soit sa durée.
- (void)_exportVideoDurationSeconds:(NSInteger)seconds toURL:(NSURL *)url {
    CAMState *exportCam = cam_create(_cam->size);
    if (!exportCam) {
        [self _showExportAlertWithMessage:@"Impossible d'allouer la grille d'export."];
        return;
    }
    uint32_t total = _cam->width * _cam->height;
    memcpy(exportCam->plane0_a, _cam->plane0_a, total);
    memcpy(exportCam->plane1_a, _cam->plane1_a, total);
    memcpy(exportCam->plane2_a, _cam->plane2_a, total);
    memcpy(exportCam->plane3_a, _cam->plane3_a, total);
    exportCam->margolus_phase = _cam->margolus_phase;

    [[NSFileManager defaultManager] removeItemAtURL:url error:nil]; // AVAssetWriter refuse d'écraser

    NSError *error = nil;
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:url fileType:AVFileTypeMPEG4 error:&error];
    if (!writer) {
        cam_destroy(exportCam);
        [self _showExportAlertWithMessage:error.localizedDescription ?: @"Échec de création du writer vidéo."];
        return;
    }

    const NSInteger fps = 30;
    const NSInteger totalFrames = seconds * fps;
    uint32_t w = exportCam->width;
    uint32_t h = exportCam->height;

    // Échelle : "auto" vise ~768 px de côté comme avant (tient dans un
    // écran 1280x800 en plein écran) ; sinon la valeur tapée dans le
    // champ (0.5, 1, 2, 3...) multiplie directement la taille NATIVE
    // de la grille — permet aussi bien un export allégé (0.5x) qu'un
    // agrandissement supérieur à 3x.
    NSString *scaleText = [_videoScaleField.stringValue stringByTrimmingCharactersInSet:
                            [NSCharacterSet whitespaceCharacterSet]];
    double scale;
    if (scaleText.length == 0 || [scaleText caseInsensitiveCompare:@"auto"] == NSOrderedSame) {
        double autoScale = 768.0 / (double)w;
        scale = (autoScale < 1.0) ? 1.0 : autoScale;
    } else {
        scale = [scaleText doubleValue];
        if (scale <= 0.0) scale = 1.0; // saisie invalide (texte, zéro, négatif) : repli sûr
        if (scale > 8.0) scale = 8.0;   // garde-fou : évite une vidéo démesurée par erreur de frappe
    }

    uint32_t vw = (uint32_t)round(w * scale);
    uint32_t vh = (uint32_t)round(h * scale);
    if (vw < 16) vw = 16; // garde-fou : jamais une vidéo degenerée (ex. 0.01x)
    if (vh < 16) vh = 16;
    if (vw % 2 != 0) vw += 1; // H.264 exige des dimensions paires
    if (vh % 2 != 0) vh += 1;

    NSDictionary *videoSettings = @{
        AVVideoCodecKey:   AVVideoCodecTypeH264,
        AVVideoWidthKey:   @(vw),
        AVVideoHeightKey:  @(vh),
    };
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                                     outputSettings:videoSettings];
    input.expectsMediaDataInRealTime = NO;

    NSDictionary *pixelBufferAttrs = @{
        (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (NSString *)kCVPixelBufferWidthKey:  @(vw),
        (NSString *)kCVPixelBufferHeightKey: @(vh),
    };
    AVAssetWriterInputPixelBufferAdaptor *adaptor =
        [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
                                                                            sourcePixelBufferAttributes:pixelBufferAttrs];
    [writer addInput:input];
    [writer startWriting];
    [writer startSessionAtSourceTime:kCMTimeZero];

    dispatch_queue_t queue = dispatch_queue_create("net.labynet.cam8.videoexport", DISPATCH_QUEUE_SERIAL);
    __block NSInteger frameIndex = 0;
    __weak Document *weakSelf = self;

    [input requestMediaDataWhenReadyOnQueue:queue usingBlock:^{
        Document *strongSelf = weakSelf;
        if (!strongSelf) { cam_destroy(exportCam); return; }

        while (input.isReadyForMoreMediaData && frameIndex < totalFrames) {
            CVPixelBufferRef pixelBuffer = NULL;
            CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &pixelBuffer);
            if (!pixelBuffer) break;

            [strongSelf _fillPixelBuffer:pixelBuffer fromCAM:exportCam scale:scale];

            CMTime frameTime = CMTimeMake(frameIndex, (int32_t)fps);
            [adaptor appendPixelBuffer:pixelBuffer withPresentationTime:frameTime];
            CVPixelBufferRelease(pixelBuffer);

            cam_step(exportCam); // avance le CLONE, jamais la grille visible
            frameIndex++;
        }

        if (frameIndex >= totalFrames) {
            [input markAsFinished];
            [writer finishWritingWithCompletionHandler:^{
                cam_destroy(exportCam);
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (writer.status == AVAssetWriterStatusFailed) {
                        [weakSelf _showExportAlertWithMessage:writer.error.localizedDescription ?: @"Échec de l'écriture vidéo."];
                    }
                });
            }];
        }
    }];
}

// scale a virgule (0.5, 1, 2, 3...) : echantillonnage au plus proche
// voisin dans les DEUX directions plutot que la replication de blocs
// entiers — generalise proprement a l'agrandissement ET a la reduction
// (la replication de blocs ne savait faire QUE l'agrandissement entier).
- (void)_fillPixelBuffer:(CVPixelBufferRef)pixelBuffer fromCAM:(CAMState *)cam scale:(double)scale {
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);

    uint8_t *dest = (uint8_t *)CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    uint32_t w = cam->width;
    uint32_t h = cam->height;
    uint32_t vw = (uint32_t)(bytesPerRow / 4);
    uint32_t vh = (uint32_t)CVPixelBufferGetHeight(pixelBuffer);
    int vis = [CAMPalettePanel sharedPalette].visibleMask;

    // Meme technique que CAMView.renderFrame : table de 16 couleurs
    // precalculee une fois, plutot qu'un appel a cam_palette() (jusqu'a
    // 5 branches) par ligne source. Le masque de visibilite est deja
    // applique en amont, sur le nibble d'index -- la table elle-meme
    // sert pour toutes les combinaisons de visibilite.
    uint8_t table[16][3];
    for (int n = 0; n < 16; n++)
        cam_palette(n & 1, (n >> 1) & 1, (n >> 2) & 1, (n >> 3) & 1,
                    &table[n][0], &table[n][1], &table[n][2]);

    // Cache par ligne SOURCE (évite de retraiter la même ligne quand
    // scale > 1 : plusieurs pixels de sortie retombent sur la même
    // cellule source).
    uint8_t *lastRowRGB = malloc((size_t)w * 3);
    uint32_t lastSourceY = UINT32_MAX;

    for (uint32_t oy = 0; oy < vh; oy++) {
        uint32_t sy = (uint32_t)(oy / scale);
        if (sy >= h) sy = h - 1;

        if (sy != lastSourceY) {
            for (uint32_t x = 0; x < w; x++) {
                size_t si = (size_t)sy * w + x;
                uint8_t nibble = ((vis & 1) ? cam->plane0_a[si] : 0)
                                | (((vis & 2) ? cam->plane1_a[si] : 0) << 1)
                                | (((vis & 4) ? cam->plane2_a[si] : 0) << 2)
                                | (((vis & 8) ? cam->plane3_a[si] : 0) << 3);
                uint8_t *rgb = table[nibble];
                lastRowRGB[x * 3 + 0] = rgb[0];
                lastRowRGB[x * 3 + 1] = rgb[1];
                lastRowRGB[x * 3 + 2] = rgb[2];
            }
            lastSourceY = sy;
        }

        uint8_t *row = dest + (size_t)oy * bytesPerRow;
        for (uint32_t ox = 0; ox < vw; ox++) {
            uint32_t sx = (uint32_t)(ox / scale);
            if (sx >= w) sx = w - 1;
            size_t idx = (size_t)ox * 4;
            row[idx + 0] = lastRowRGB[sx * 3 + 2]; // B
            row[idx + 1] = lastRowRGB[sx * 3 + 1]; // G
            row[idx + 2] = lastRowRGB[sx * 3 + 0]; // R
            row[idx + 3] = 255;
        }
    }

    free(lastRowRGB);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
}

- (void)_showExportAlertWithMessage:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Export vidéo — erreur";
    alert.informativeText = message ?: @"Erreur inconnue.";
    alert.alertStyle = NSAlertStyleWarning;
    [alert runModal];
}

#pragma mark - Save / Load (NSDocument)

// Appelé par Cmd+S / Cmd+Maj+S : sérialise le texte de la règle telle quelle.
- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError {
    NSString *source = self.ruleTextView ? self.ruleTextView.string : (_pendingRuleSource ?: @"");
    NSData *data = [source dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                             code:NSFileWriteUnknownError
                                         userInfo:@{NSLocalizedDescriptionKey: @"Impossible d'encoder la règle en UTF-8."}];
        }
        return nil;
    }
    return data;
}

// Appelé par Cmd+O (ou double-clic sur un fichier) : peut arriver AVANT
// que la fenêtre existe, d'où le stockage temporaire dans _pendingRuleSource.
- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError {
    NSString *source = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!source) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                             code:NSFileReadCorruptFileError
                                         userInfo:@{NSLocalizedDescriptionKey: @"Fichier de règle illisible (encodage invalide, attendu UTF-8)."}];
        }
        return NO;
    }

    _pendingRuleSource = source;

    // Si la fenêtre est déjà construite (rechargement d'un document déjà ouvert),
    // on applique tout de suite au lieu d'attendre windowControllerDidLoadNib:.
    if (self.ruleTextView) {
        self.ruleTextView.string = source;
        _pendingRuleSource = nil;
    }

    return YES;
}

// Note : n'appelle PAS cam_set_rule — seul un clic sur "Compiler la Règle"
// doit modifier la LUT du moteur CAM.
- (void)_clearPlanes {
    // "Effacer tout" au sens strict : les QUATRE plans, buffers courants
    // ET suivants (sinon un swap peut ressusciter l'ancien état).
    uint32_t total = _cam->width * _cam->height;
    memset(_cam->plane0_a, 0, total); memset(_cam->plane0_b, 0, total);
    memset(_cam->plane1_a, 0, total); memset(_cam->plane1_b, 0, total);
    memset(_cam->plane2_a, 0, total); memset(_cam->plane2_b, 0, total);
    memset(_cam->plane3_a, 0, total); memset(_cam->plane3_b, 0, total);
    // Efface aussi le gaz FHP (les 6 canaux ET les obstacles peints) —
    // sans condition sur fhpMode : "tout" veut dire tout, y compris ce
    // qu'on ne regarde pas actuellement.
    if (_fhp) fhp_clear(_fhp);
    [_camView renderFrame];
}

- (void)_randomizePlanes:(int)density {
    // Mode FHP : seme le gaz sur les 6 canaux directionnels (pas de
    // notion de "plan selectionne" ici — le gaz n'a que ses 6 directions).
    if ([CAMPalettePanel sharedPalette].fhpMode && _fhp) {
        for (int d = 0; d < 6; d++) fhp_seed_random(_fhp, (FHPDirection)d, density);
        [_camView renderFrame];
        return;
    }

    // Sème dans le plan SÉLECTIONNÉ de la palette, sans toucher aux
    // autres : le décor (germes, parois, chronos CAM-B) survit au Lancer.
    // "Effacer tout" reste le moyen de vraiment tout vider.
    uint32_t total = _cam->width * _cam->height;
    int plane = [CAMPalettePanel sharedPalette].currentPlane;
    uint8_t *grids_a[4] = { _cam->plane0_a, _cam->plane1_a, _cam->plane2_a, _cam->plane3_a };
    uint8_t *grids_b[4] = { _cam->plane0_b, _cam->plane1_b, _cam->plane2_b, _cam->plane3_b };
    memset(grids_a[plane & 3], 0, total);
    memset(grids_b[plane & 3], 0, total);
    for (uint32_t i = 0; i < total; i++)
        grids_a[plane & 3][i] = (arc4random_uniform(100) < (uint32_t)density);
    [_camView renderFrame];
}


#pragma mark - N/USER : coller un bitmap (Cmd+V)

// L'interprétation logicielle du connecteur N/USER du CAM-6 : le monde
// extérieur entre par le presse-papier. L'image est ajustée-centrée dans
// la grille, seuillée à 50%% de luminance, avec polarité automatique
// (la figure = le camp minoritaire de pixels). Seul le plan sélectionné
// dans la palette est écrasé.
- (IBAction)paste:(id)sender {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSArray *found = [pb readObjectsForClasses:@[[NSImage class]] options:nil];
    NSImage *img = found.firstObject;
    if (!img || !_cam) { NSBeep(); return; }

    uint32_t gw = _cam->width, gh = _cam->height;

    // rendu de l'image dans un bitmap RGBA à la taille de la grille,
    // ajusté et centré
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL pixelsWide:gw pixelsHigh:gh
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSCalibratedRGBColorSpace
        bytesPerRow:gw * 4 bitsPerPixel:32];
    if (!rep) { NSBeep(); return; }

    NSSize isz = img.size;
    CGFloat scale = MIN((CGFloat)gw / isz.width, (CGFloat)gh / isz.height);
    NSRect dst = NSMakeRect((gw - isz.width * scale) / 2.0,
                            (gh - isz.height * scale) / 2.0,
                            isz.width * scale, isz.height * scale);

    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext setCurrentContext:ctx];
    [[NSColor blackColor] setFill];
    NSRectFill(NSMakeRect(0, 0, gw, gh));
    [img drawInRect:dst fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    [ctx flushGraphics];
    [NSGraphicsContext restoreGraphicsState];

    // seuillage et polarité, calculés DANS le rectangle de l'image
    // seulement (sinon le letterboxing noir fausse le vote et le fond
    // blanc d'un logo devient la "figure"). Les pixels transparents ne
    // touchent pas au plan : on peut composer plusieurs collages.
    unsigned char *px = rep.bitmapData;
    int x0 = (int)NSMinX(dst), x1 = (int)NSMaxX(dst);
    int y0 = (int)NSMinY(dst), y1 = (int)NSMaxY(dst);
    if (x0 < 0) x0 = 0; if (y0 < 0) y0 = 0;
    if (x1 > (int)gw) x1 = gw; if (y1 > (int)gh) y1 = gh;

    uint32_t bright = 0, opaque = 0;
    for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
            unsigned char *p = px + (y * gw + x) * 4;
            if (p[3] < 128) continue;
            opaque++;
            int lum = (299 * p[0] + 587 * p[1] + 114 * p[2]) / 1000;
            if (lum > 127) bright++;
        }
    }
    // la figure est le camp minoritaire du rectangle
    int bright_is_figure = (bright <= opaque / 2);

    int plane = [CAMPalettePanel sharedPalette].currentPlane;
    uint8_t *grids_a[4] = { _cam->plane0_a, _cam->plane1_a, _cam->plane2_a, _cam->plane3_a };
    uint8_t *grids_b[4] = { _cam->plane0_b, _cam->plane1_b, _cam->plane2_b, _cam->plane3_b };
    for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
            unsigned char *p = px + (y * gw + x) * 4;
            if (p[3] < 128) continue; // transparent : on ne touche pas
            int lum = (299 * p[0] + 587 * p[1] + 114 * p[2]) / 1000;
            int is_bright = (lum > 127);
            grids_a[plane & 3][y * gw + x] =
                (is_bright == bright_is_figure) ? 1 : 0;
        }
    }
    memcpy(grids_b[plane & 3], grids_a[plane & 3], (size_t)gw * gh);
    [_camView renderFrame];
}


@end
