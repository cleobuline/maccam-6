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
    CAMToolEraser,
    CAMToolSpray // densite aleatoire dans le rayon ; en mode FHP, vent dirige HEX-E
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

// Mode FHP (chapitre 16) : quand actif, la grille bascule entierement
// sur le sous-systeme gaz FHP (fhp.h/.c) au lieu de CAM-A/CAM-B/Margolus.
// Rien dans le chemin normal n'est modifie par ce mode : c'est un
// aiguillage propre dans Document.m et CAMView.m, jamais actif par
// defaut (FALSE au demarrage).
@property (nonatomic, assign) BOOL      fhpMode;

// Vent continu (chapitre 16) : reinjecte du gaz sur HEX-E le long du
// bord gauche a CHAQUE pas, tant que Play tourne. Sans ca, Spray n'est
// qu'un coup de pinceau ponctuel qui se disperse et s'equilibre --
// jamais un vrai flux etabli capable de former un sillage stable
// derriere un obstacle. Sans effet si fhpMode est OFF.
@property (nonatomic, assign) BOOL      continuousWind;

// Bords ouverts (chapitre 16) : le gaz qui atteint le bord DROIT sort
// du domaine au lieu de reapparaitre a gauche par le tore. Sans ca,
// avec Vent continu, le gaz appauvri par un obstacle finit par
// recirculer et former des artefacts de bandes stagnantes au lieu
// d'un vrai sillage. Sans effet si fhpMode est OFF.
@property (nonatomic, assign) BOOL      openChannel;

// FHP-II (chapitre 16, particules au repos) : probabilite (0-100)
// qu'une collision frontale a 2 corps soit absorbee en particules au
// repos plutot que devier -- le bouton de viscosite qui manquait a
// FHP-I. A 0 (defaut), comportement identique a FHP-I.
@property (nonatomic, assign) int       fhpViscosity;

// callbacks vers Document
@property (nonatomic, copy) void (^onReverse)(void);
@property (nonatomic, copy) void (^onPlayPause)(BOOL running);
@property (nonatomic, copy) void (^onRandomize)(int density);
@property (nonatomic, copy) void (^onClear)(void);
// mode: 128, 256, 512 ou 1024
@property (nonatomic, copy) void (^onSizeChange)(int size);
@property (nonatomic, copy) void (^onFPSChange)(int fps);

+ (instancetype)sharedPalette;
- (void)showPalette;

@end
