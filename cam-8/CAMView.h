#ifndef CAMView_h
#define CAMView_h

#import <Cocoa/Cocoa.h>
#include "cam_core.h"
#include "fph.h"
#import "CAMPalettePanel.h"

@interface CAMView : NSView

@property (nonatomic, assign) CAMState      *camState;
@property (nonatomic, weak)   CAMPalettePanel *palette;

// Sous-systeme FHP (chapitre 16), independant de camState. Non-nil et
// utilise seulement quand palette.fhpMode est actif -- sinon CAMView se
// comporte exactement comme avant, chemin CAM inchange.
@property (nonatomic, assign) FHPState      *fhpState;

- (void)renderFrame;

@end

#endif
