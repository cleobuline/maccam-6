//
//  fhp.h
//  cam-8 — chapitre 16 : gaz de Frisch-Hasslacher-Pomeau
//
//  Sous-systeme ENTIEREMENT ISOLE du reste du moteur (cam_core.c,
//  cam_forth.c). Aucun fichier existant n'est modifie pour l'integrer :
//  FHPState est une structure a part, avec son propre create/destroy/step.
//  L'integration dans l'app (si souhaitee) se fait en ADDITION pure,
//  jamais en modification des chemins CAM-A/CAM-B/Margolus/HEX-mono-plan
//  qui fonctionnent deja.
//
//  Pourquoi un sous-systeme a part et pas une extension de CAMState ?
//  Le vrai gaz FHP a besoin de 6 bits par cellule (un par direction a
//  60 degres) pour encoder une particule EN MOUVEMENT — un CA a un seul
//  bit par cellule (comme N/HEX ou CAM-A/CAM-B) ne peut representer que
//  de la densite/diffusion, jamais du transport avec quantite de
//  mouvement (voir le test de conservation qui a fait echouer la
//  premiere tentative de regle FHP-GAS en Forth).
//

#ifndef CAM8_FHP_H
#define CAM8_FHP_H

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// Les 6 directions a 60 degres, memes conventions que N/HEX dans
// cam_forth.h (encodage even-r : E, NE, NW, W, SW, SE).
typedef enum {
    FHP_DIR_E  = 0,
    FHP_DIR_NE = 1,
    FHP_DIR_NW = 2,
    FHP_DIR_W  = 3,
    FHP_DIR_SW = 4,
    FHP_DIR_SE = 5
} FHPDirection;

// direction opposee : E<->W, NE<->SW, NW<->SE
static inline FHPDirection fhp_opposite(FHPDirection d) {
    return (FHPDirection)((d + 3) % 6);
}

typedef struct {
    uint32_t width;
    uint32_t height;

    // 6 plans booleens, un par direction, double-tamponnes.
    uint8_t *dir_a[6];
    uint8_t *dir_b[6];

    // Obstacle (mur, cylindre...) : UN plan, non double-tamponne — le
    // decor ne bouge pas. Les particules qui l'atteignent rebondissent
    // (bounce-back complet, la condition aux limites classique pour
    // simuler un solide immobile dans le gaz).
    uint8_t *obstacle;

    // Graine du generateur de nombres pseudo-aleatoires DEDIEE a ce
    // sous-systeme (pas celle de cam_core.c) : deux mondes independants.
    uint32_t rng_state;

    // Bords ouverts (chapitre 16, soufflerie) : quand actif, tout ce qui
    // atteint le bord DROIT (x = width-1) disparaît a la transport au
    // lieu de reapparaitre a gauche par le tore. Indispensable pour une
    // vraie scene "vent + obstacle" : sans ca, le gaz appauvri par
    // l'obstacle finit par recirculer et boucler sur lui-meme, ce qui
    // ressemble a une bande stagnante bien plus qu'a un sillage.
    // Desactive par defaut : le comportement torique d'origine (utile
    // pour les bancs d'essai d'isotropie) n'est pas remis en cause.
    int open_right_edge;
} FHPState;

FHPState *fhp_create(uint32_t width, uint32_t height);
void      fhp_destroy(FHPState *fhp);

// Vide tout (gaz + obstacles).
void fhp_clear(FHPState *fhp);

// Remplit une direction avec une densite aleatoire (0-100).
void fhp_seed_random(FHPState *fhp, FHPDirection dir, int density_percent);

// Pose/retire un obstacle ponctuel (mur, cylindre construit cellule
// par cellule depuis l'app ou un test).
void fhp_set_obstacle(FHPState *fhp, uint32_t x, uint32_t y, int present);

// Un pas complet : collision puis transport. Void inline.
void fhp_step(FHPState *fhp);

// Accesseurs pratiques pour l'affichage / les tests :
//  - densite totale (nombre de bits allumes, toutes directions confondues)
//  - densite locale a une cellule (0-6)
int      fhp_total_population(const FHPState *fhp);
uint8_t  fhp_local_density(const FHPState *fhp, uint32_t x, uint32_t y);

#endif
