#ifndef CAMView_h
#define CAMView_h

#import <Cocoa/Cocoa.h>
#include "cam_core.h"
#import "CAMPalettePanel.h"

@interface CAMView : NSView

@property (nonatomic, assign) CAMState      *camState;
@property (nonatomic, weak)   CAMPalettePanel *palette;
@property (nonatomic, assign) int visibleMask;
- (void)renderFrame;

@end

#endif
