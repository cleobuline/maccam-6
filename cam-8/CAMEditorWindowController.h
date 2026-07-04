////
//  CAMEditorWindowController.h
//  cam-8
//

#import <Cocoa/Cocoa.h>
#include "cam_core.h"

@interface CAMEditorWindowController : NSWindowController

@property (nonatomic, assign) CAMState *camState;

// callback appelé quand une règle est compilée avec succès
@property (nonatomic, copy) void (^onRuleCompiled)(void);

+ (instancetype)sharedEditor;
- (void)showEditor;

@end
