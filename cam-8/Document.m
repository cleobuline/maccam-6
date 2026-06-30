//
//  Document.m
//  cam-8
//
//  Created by Patricia Benedetto on 29/06/2026.
//

#import "Document.h"
#import "CAMView.h"
#include "cam_core.h"

@interface Document () {
    CAMState *_cam;
    CAMView  *_camView;
}
@end

@implementation Document

- (instancetype)init {
    self = [super init];
    if (self) {
        // Crée une grille 256x256
        _cam = cam_create(CAM_SIZE_256);

        // Rempli avec du bruit aléatoire
        uint32_t total = _cam->width * _cam->height;
        for (uint32_t i = 0; i < total; i++) {
            _cam->grid_a[i] = (uint8_t)arc4random_uniform(256);
        }
    }
    return self;
}

- (void)dealloc {
    cam_destroy(_cam);
}

+ (BOOL)autosavesInPlace {
    return YES;
}

- (NSString *)windowNibName {
    return @"Document";
}

- (void)windowControllerDidLoadNib:(NSWindowController *)windowController {
    [super windowControllerDidLoadNib:windowController];

    // Crée la CAMView aux dimensions de la fenêtre
    NSView *contentView = windowController.window.contentView;
    NSRect frame = contentView.bounds;

    _camView = [[CAMView alloc] initWithFrame:frame];
    _camView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _camView.camState = _cam;

    [contentView addSubview:_camView];
    [_camView renderFrame];
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError {
    if (outError) {
        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                        code:unimpErr
                                    userInfo:nil];
    }
    return nil;
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError {
    if (outError) {
        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                        code:unimpErr
                                    userInfo:nil];
    }
    return YES;
}

@end
