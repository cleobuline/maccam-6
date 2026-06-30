//
//  CAMView.h
//  cam-8
//
//  Created by Patricia Benedetto on 29/06/2026.
//

#ifndef CAMView_h
#define CAMView_h

#import <Cocoa/Cocoa.h>
#include "cam_core.h"

@interface CAMView : NSView

@property (nonatomic, assign) CAMState *camState;

- (void)renderFrame;

@end

#endif /* CAMView_h */
