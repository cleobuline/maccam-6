//
//  CAMPalettePanel.h
//  cam-8
//

#import <Cocoa/Cocoa.h>
#include "cam_core.h"

typedef NS_ENUM(NSInteger, CAMTool) {
    CAMToolPencil = 0,
    CAMToolCircle,
    CAMToolSquare,
    CAMToolEraser
};

@interface CAMPalettePanel : NSPanel

@property (nonatomic, assign) CAMState *camState;
@property (nonatomic, assign) CAMTool   currentTool;
@property (nonatomic, assign) int       brushSize;
@property (nonatomic, assign) int       density;
@property (nonatomic, assign) int       currentPlane;  // 0 à 3
// bits 0-3 : visibilité des plans à l'AFFICHAGE (la simulation, elle,
// calcule toujours tout) — l'équivalent des color maps du CAM-6.
@property (nonatomic, assign) int       visibleMask;
@property (nonatomic, assign) BOOL      isRunning;

// callbacks vers Document
@property (nonatomic, copy) void (^onReverse)(void);
@property (nonatomic, copy) void (^onPlayPause)(BOOL running);
@property (nonatomic, copy) void (^onRandomize)(int density);
@property (nonatomic, copy) void (^onClear)(void);
// mode: 128, 256, 512 ou 1024
@property (nonatomic, copy) void (^onSizeChange)(int size);

+ (instancetype)sharedPalette;
- (void)showPalette;

@end
