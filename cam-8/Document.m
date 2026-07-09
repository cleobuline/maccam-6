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
    CAMState *_exportCam; // non-NULL PENDANT un export en cours ; permet a
                          // compileRule: de resynchroniser le clone avec
                          // la grille visible (voir _exportVideoDurationSeconds:)
    BOOL _pendingExportReverse; // LE SIGNAL SYNCHRONE POUR L'INVERSION TEMPORELLE
    BOOL _pendingExportSync;    // LE SIGNAL SYNCHRONE POUR LE DESSIN ET LA COMPILATION
}
@property (nonatomic, assign) BOOL isRunning;
@end

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
        _fhp = fhp_create(_cam->width, _cam->height); // toujours cree, mais inerte tant que fhpMode is OFF
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

    // Nettoyage du placeholder par défaut
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
    exportBtn.frame = NSMakeRect(60, 10, 56, 30);
    exportBtn.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    exportBtn.font = [NSFont systemFontOfSize:16];
    [(NSButtonCell *)exportBtn.cell setLineBreakMode:NSLineBreakByClipping];
    exportBtn.toolTip = @"Exporter en vidéo…";
    [editorContainer addSubview:exportBtn];

    _videoScaleField = [NSTextField textFieldWithString:@"auto"];
    _videoScaleField.frame = NSMakeRect(124, 14, 60, 22);
    _videoScaleField.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    _videoScaleField.alignment = NSTextAlignmentCenter;
    _videoScaleField.toolTip = @"Échelle vidéo : \"auto\" (~768px), ou une valeur comme 0.5, 1, 2, 3 — multiplie la taille native de la grille.";
    [editorContainer addSubview:_videoScaleField];

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
    palette.onClearPlane = ^(int plane) { [weakSelf _clearPlane:plane]; };
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
            strongSelf->_timeReversed = !strongSelf->_timeReversed;
        } else {
            uint8_t *tmp = strongSelf->_cam->plane0_a;
            strongSelf->_cam->plane0_a = strongSelf->_cam->plane1_a;
            strongSelf->_cam->plane1_a = tmp;
            [strongSelf->_camView renderFrame];
            
            strongSelf->_pendingExportReverse = YES;
        }
    };
    [palette showPalette];

    _camView.palette = palette;
    palette.camState = _cam;
    palette.isRunning = self.isRunning;

    // --- INTERCEPTION DU PINCEAU POUR L'EXPORT ASYNCHRONE ---
    _camView.onGridPainted = ^{
        Document *strongSelf = weakSelf;
        if (strongSelf && strongSelf->_exportCam) {
            strongSelf->_pendingExportSync = YES;
        }
    };
    // --------------------------------------------------------

    [self _randomizePlanes:50];
    CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    CVDisplayLinkSetOutputCallback(_displayLink, &DisplayLinkCallback, (__bridge void *)self);
    CVDisplayLinkStart(_displayLink);
}

- (void)_recreateGridAtSize:(int)newSize {
    CAMGridSize size;
    switch (newSize) {
        case 128:  size = CAM_SIZE_128;  break;
        case 512:  size = CAM_SIZE_512;  break;
        case 1024: size = CAM_SIZE_1024; break;
        default:   size = CAM_SIZE_256;  break;
    }
    if (_cam && _cam->size == size) return;

    BOOL wasRunning = self.isRunning;
    self.isRunning = NO;
    _timeReversed = NO;

    CAMState *old = _cam;
    CAMState *fresh = cam_create(size);
    if (!fresh) { NSBeep(); return; }

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

    // --- ABANDON DU MEMCPY DIRECT SUR LE MAIN THREAD ---
    if (_exportCam && _exportCam->width == _cam->width && _exportCam->height == _cam->height) {
        _pendingExportSync = YES; // Signal envoyé à la fonderie
    }
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
    if (seconds > 600) seconds = 600;

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

- (void)_exportVideoDurationSeconds:(NSInteger)seconds toURL:(NSURL *)url {
    CAMState *exportCam = cam_create(_cam->size);
    if (!exportCam) {
        [self _showExportAlertWithMessage:@"Impossible d'allouer la grille d'export."];
        return;
    }
    _exportCam = exportCam;
    uint32_t total = _cam->width * _cam->height;
    memcpy(exportCam->plane0_a, _cam->plane0_a, total);
    memcpy(exportCam->plane1_a, _cam->plane1_a, total);
    memcpy(exportCam->plane2_a, _cam->plane2_a, total);
    memcpy(exportCam->plane3_a, _cam->plane3_a, total);
    exportCam->margolus_phase = _cam->margolus_phase;

    [[NSFileManager defaultManager] removeItemAtURL:url error:nil];

    NSError *error = nil;
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:url fileType:AVFileTypeMPEG4 error:&error];
    if (!writer) {
        cam_destroy(exportCam);
        _exportCam = NULL;
        [self _showExportAlertWithMessage:error.localizedDescription ?: @"Échec de création du writer vidéo."];
        return;
    }

    const NSInteger fps = 30;
    const NSInteger totalFrames = seconds * fps;
    uint32_t w = exportCam->width;
    uint32_t h = exportCam->height;

    NSString *scaleText = [_videoScaleField.stringValue stringByTrimmingCharactersInSet:
                            [NSCharacterSet whitespaceCharacterSet]];
    double scale;
    if (scaleText.length == 0 || [scaleText caseInsensitiveCompare:@"auto"] == NSOrderedSame) {
        double autoScale = 768.0 / (double)w;
        scale = (autoScale < 1.0) ? 1.0 : autoScale;
    } else {
        scale = [scaleText doubleValue];
        if (scale <= 0.0) scale = 1.0;
        if (scale > 8.0) scale = 8.0;
    }

    uint32_t vw = (uint32_t)round(w * scale);
    uint32_t vh = (uint32_t)round(h * scale);
    if (vw < 16) vw = 16;
    if (vh < 16) vh = 16;
    if (vw % 2 != 0) vw += 1;
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
            
            // --- PROTECTION ET CONSOMMATION DES SIGNAUX SUR LE BACKGROUND THREAD ---
            if (strongSelf->_pendingExportReverse) {
                uint8_t *tmpExport = exportCam->plane0_a;
                exportCam->plane0_a = exportCam->plane1_a;
                exportCam->plane1_a = tmpExport;
                strongSelf->_pendingExportReverse = NO;
            }

            if (strongSelf->_pendingExportSync) {
                uint32_t totalPlanes = strongSelf->_cam->width * strongSelf->_cam->height;
                memcpy(exportCam->plane0_a, strongSelf->_cam->plane0_a, totalPlanes);
                memcpy(exportCam->plane1_a, strongSelf->_cam->plane1_a, totalPlanes);
                memcpy(exportCam->plane2_a, strongSelf->_cam->plane2_a, totalPlanes);
                memcpy(exportCam->plane3_a, strongSelf->_cam->plane3_a, totalPlanes);
                exportCam->margolus_phase = strongSelf->_cam->margolus_phase;
                strongSelf->_pendingExportSync = NO;
            }
            // ------------------------------------------------------------------------

            CVPixelBufferRef pixelBuffer = NULL;
            CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &pixelBuffer);
            if (!pixelBuffer) break;

            [strongSelf _fillPixelBuffer:pixelBuffer fromCAM:exportCam scale:scale];

            CMTime frameTime = CMTimeMake(frameIndex, (int32_t)fps);
            [adaptor appendPixelBuffer:pixelBuffer withPresentationTime:frameTime];
            CVPixelBufferRelease(pixelBuffer);

            if (strongSelf.isRunning) {
                if (strongSelf->_timeReversed && cam_can_reverse()) {
                    cam_step_back(exportCam);
                } else {
                    cam_step(exportCam);
                }
            }
            frameIndex++;
        }

        if (frameIndex >= totalFrames) {
            [input markAsFinished];
            [writer finishWritingWithCompletionHandler:^{
                cam_destroy(exportCam);
                Document *doneSelf = weakSelf;
                if (doneSelf) doneSelf->_exportCam = NULL;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (writer.status == AVAssetWriterStatusFailed) {
                        [weakSelf _showExportAlertWithMessage:writer.error.localizedDescription ?: @"Échec de l'écriture vidéo."];
                    }
                });
            }];
        }
    }];
}

- (void)_fillPixelBuffer:(CVPixelBufferRef)pixelBuffer fromCAM:(CAMState *)cam scale:(double)scale {
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);

    uint8_t *dest = (uint8_t *)CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    uint32_t w = cam->width;
    uint32_t h = cam->height;
    uint32_t vw = (uint32_t)(bytesPerRow / 4);
    uint32_t vh = (uint32_t)CVPixelBufferGetHeight(pixelBuffer);
    int vis = [CAMPalettePanel sharedPalette].visibleMask;

    uint8_t table[16][3];
    for (int n = 0; n < 16; n++)
        cam_palette(n & 1, (n >> 1) & 1, (n >> 2) & 1, (n >> 3) & 1,
                    &table[n][0], &table[n][1], &table[n][2]);

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

    if (self.ruleTextView) {
        self.ruleTextView.string = source;
        _pendingRuleSource = nil;
    }

    return YES;
}
- (void)_clearPlane:(int)plane {
    if (!_cam) return;
    uint32_t total = _cam->width * _cam->height;
    uint8_t *grids_a[4] = { _cam->plane0_a, _cam->plane1_a, _cam->plane2_a, _cam->plane3_a };
    uint8_t *grids_b[4] = { _cam->plane0_b, _cam->plane1_b, _cam->plane2_b, _cam->plane3_b };
    
    // Effacement strict du plan ciblé
    memset(grids_a[plane & 3], 0, total);
    memset(grids_b[plane & 3], 0, total);
    
    [_camView renderFrame];
    
    // Interception pour la fonderie vidéo si un export est en cours
    if (_exportCam) {
        _pendingExportSync = YES;
    }
}
- (void)_clearPlanes {
    uint32_t total = _cam->width * _cam->height;
    memset(_cam->plane0_a, 0, total); memset(_cam->plane0_b, 0, total);
    memset(_cam->plane1_a, 0, total); memset(_cam->plane1_b, 0, total);
    memset(_cam->plane2_a, 0, total); memset(_cam->plane2_b, 0, total);
    memset(_cam->plane3_a, 0, total); memset(_cam->plane3_b, 0, total);
    if (_fhp) fhp_clear(_fhp);
    [_camView renderFrame];
}

- (void)_randomizePlanes:(int)density {
    if ([CAMPalettePanel sharedPalette].fhpMode && _fhp) {
        for (int d = 0; d < 6; d++) fhp_seed_random(_fhp, (FHPDirection)d, density);
        [_camView renderFrame];
        return;
    }

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

- (IBAction)paste:(id)sender {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSArray *found = [pb readObjectsForClasses:@[[NSImage class]] options:nil];
    NSImage *img = found.firstObject;
    if (!img || !_cam) { NSBeep(); return; }

    uint32_t gw = _cam->width, gh = _cam->height;

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
    int bright_is_figure = (bright <= opaque / 2);

    int plane = [CAMPalettePanel sharedPalette].currentPlane;
    uint8_t *grids_a[4] = { _cam->plane0_a, _cam->plane1_a, _cam->plane2_a, _cam->plane3_a };
    uint8_t *grids_b[4] = { _cam->plane0_b, _cam->plane1_b, _cam->plane2_b, _cam->plane3_b };
    for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
            unsigned char *p = px + (y * gw + x) * 4;
            if (p[3] < 128) continue;
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
