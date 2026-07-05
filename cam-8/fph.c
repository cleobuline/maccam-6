//
//  fhp.c
//  cam-8 — chapitre 16
//
//  Implementation isolee. Duplique volontairement une petite fonction
//  d'adressage hexagonal (deja ecrite dans cam_core.c pour N/HEX) plutot
//  que de partager du code entre les deux sous-systemes : l'isolation
//  totale est le prix a payer pour ne rien risquer sur ce qui tourne
//  deja. Le schema est identique (even-r, brickwork) et a ete valide
//  par les tests d'isotropie de N/HEX.
//

#include "fph.h"

// xorshift32 independant de celui de cam_core.c — deux mondes separes.
static inline uint32_t fhp_rng_next(FHPState *fhp) {
    uint32_t x = fhp->rng_state;
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    return fhp->rng_state = x;
}
static inline uint8_t fhp_rng_bit(FHPState *fhp) {
    return (uint8_t)(fhp_rng_next(fhp) & 1);
}

// Neighbor(X, direction, row_parity_of_X) -> coordonnees du voisin,
// avec repliement torique. Meme convention even-r que N/HEX.
static void fhp_neighbor(const FHPState *fhp, uint32_t x, uint32_t y,
                          FHPDirection d, uint32_t *nx, uint32_t *ny) {
    uint32_t w = fhp->width, h = fhp->height;
    int row_odd = y & 1;
    uint32_t x_right = (x + 1) % w;
    uint32_t x_left  = (x - 1 + w) % w;
    uint32_t y_up    = (y - 1 + h) % h;
    uint32_t y_down  = (y + 1) % h;

    switch (d) {
        case FHP_DIR_E:  *nx = x_right; *ny = y; return;
        case FHP_DIR_W:  *nx = x_left;  *ny = y; return;
        case FHP_DIR_NE:
            *ny = y_up; *nx = row_odd ? x_right : x; return;
        case FHP_DIR_NW:
            *ny = y_up; *nx = row_odd ? x : x_left; return;
        case FHP_DIR_SE:
            *ny = y_down; *nx = row_odd ? x_right : x; return;
        case FHP_DIR_SW:
            *ny = y_down; *nx = row_odd ? x : x_left; return;
    }
}

// Comme fhp_neighbor, mais SANS repliement horizontal : retourne 0 (et
// ne remplit pas nx/ny) si la destination sortirait du domaine par la
// gauche ou la droite -- c'est ce qui permet a une particule de
// "sortir" du canal au lieu de recirculer par le tore. Le repliement
// vertical (haut/bas) reste inchange : seule la dimension du courant
// (x) est ouverte, pas la dimension transverse.
static int fhp_neighbor_open(const FHPState *fhp, uint32_t x, uint32_t y,
                              FHPDirection d, uint32_t *nx, uint32_t *ny) {
    uint32_t w = fhp->width, h = fhp->height;
    int row_odd = y & 1;
    uint32_t y_up   = (y - 1 + h) % h;
    uint32_t y_down = (y + 1) % h;

    long ix, iy;

    switch (d) {
        case FHP_DIR_E:  ix = (long)x + 1; iy = y;      break;
        case FHP_DIR_W:  ix = (long)x - 1; iy = y;      break;
        case FHP_DIR_NE: iy = y_up;   ix = row_odd ? (long)x + 1 : (long)x;     break;
        case FHP_DIR_NW: iy = y_up;   ix = row_odd ? (long)x : (long)x - 1;     break;
        case FHP_DIR_SE: iy = y_down; ix = row_odd ? (long)x + 1 : (long)x;     break;
        case FHP_DIR_SW: iy = y_down; ix = row_odd ? (long)x : (long)x - 1;     break;
        default: return 0;
    }

    if (ix < 0 || ix >= (long)w) return 0; // sortie par la gauche ou la droite
    *nx = (uint32_t)ix;
    *ny = (uint32_t)iy;
    return 1;
}

FHPState *fhp_create(uint32_t width, uint32_t height) {
    FHPState *fhp = calloc(1, sizeof(FHPState));
    if (!fhp) return NULL;
    fhp->width = width;
    fhp->height = height;
    fhp->rng_state = 0x5EED1234u;

    size_t n = (size_t)width * height;
    int ok = 1;
    for (int d = 0; d < 6; d++) {
        fhp->dir_a[d] = calloc(n, 1);
        fhp->dir_b[d] = calloc(n, 1);
        if (!fhp->dir_a[d] || !fhp->dir_b[d]) ok = 0;
    }
    fhp->obstacle = calloc(n, 1);
    if (!fhp->obstacle) ok = 0;

    if (!ok) { fhp_destroy(fhp); return NULL; }
    return fhp;
}

void fhp_destroy(FHPState *fhp) {
    if (!fhp) return;
    for (int d = 0; d < 6; d++) {
        free(fhp->dir_a[d]);
        free(fhp->dir_b[d]);
    }
    free(fhp->obstacle);
    free(fhp);
}

void fhp_clear(FHPState *fhp) {
    size_t n = (size_t)fhp->width * fhp->height;
    for (int d = 0; d < 6; d++) {
        memset(fhp->dir_a[d], 0, n);
        memset(fhp->dir_b[d], 0, n);
    }
    memset(fhp->obstacle, 0, n);
}

void fhp_seed_random(FHPState *fhp, FHPDirection dir, int density_percent) {
    size_t n = (size_t)fhp->width * fhp->height;
    for (size_t i = 0; i < n; i++) {
        fhp->dir_a[dir][i] = (fhp_rng_next(fhp) % 100 < (uint32_t)density_percent) ? 1 : 0;
    }
}

void fhp_set_obstacle(FHPState *fhp, uint32_t x, uint32_t y, int present) {
    if (x >= fhp->width || y >= fhp->height) return;
    fhp->obstacle[y * fhp->width + x] = present ? 1 : 0;
}

int fhp_total_population(const FHPState *fhp) {
    size_t n = (size_t)fhp->width * fhp->height;
    int total = 0;
    for (int d = 0; d < 6; d++)
        for (size_t i = 0; i < n; i++)
            total += fhp->dir_a[d][i];
    return total;
}

uint8_t fhp_local_density(const FHPState *fhp, uint32_t x, uint32_t y) {
    if (x >= fhp->width || y >= fhp->height) return 0;
    size_t i = (size_t)y * fhp->width + x;
    uint8_t s = 0;
    for (int d = 0; d < 6; d++) s += fhp->dir_a[d][i];
    return s;
}

// Phase 1 — collision (FHP-I complet : collisions a 2 ET 3 corps).
// Sur chaque cellule NON-obstacle, on regarde les 3 paires d'axes
// opposes (E/W, NE/SW, NW/SE). Si exactement une paire est pleine et
// que les 4 autres directions sont vides (2 particules, exactement
// frontales, aucun troisieme corps), on devie vers l'UNE des deux
// paires transverses, choisie au hasard pour ne pas biaiser une
// direction de rotation. Si exactement un des deux triplets symetriques
// a 120 degres est plein (3 particules), on rotate deterministiquement
// vers l'autre triplet — c'est la regle qui manquait dans la toute
// premiere version : sans elle, le gaz possede une quantite conservee
// parasite (le nombre de triplets symetriques) qui peut le figer en
// rubans stationnaires au lieu de former un vrai sillage turbulent.
// Sinon (0, 1, ou configurations non-symetriques), rien ne change : la
// configuration traverse telle quelle vers la phase de transport.
static void fhp_collide(FHPState *fhp, uint8_t *coll[6]) {
    size_t n = (size_t)fhp->width * fhp->height;

    for (size_t i = 0; i < n; i++) {
        if (fhp->obstacle[i]) {
            // bounce-back complet : chaque particule repart d'ou elle vient
            coll[FHP_DIR_E][i]  = fhp->dir_a[FHP_DIR_W][i];
            coll[FHP_DIR_W][i]  = fhp->dir_a[FHP_DIR_E][i];
            coll[FHP_DIR_NE][i] = fhp->dir_a[FHP_DIR_SW][i];
            coll[FHP_DIR_SW][i] = fhp->dir_a[FHP_DIR_NE][i];
            coll[FHP_DIR_NW][i] = fhp->dir_a[FHP_DIR_SE][i];
            coll[FHP_DIR_SE][i] = fhp->dir_a[FHP_DIR_NW][i];
            continue;
        }

        uint8_t e  = fhp->dir_a[FHP_DIR_E][i];
        uint8_t ne = fhp->dir_a[FHP_DIR_NE][i];
        uint8_t nw = fhp->dir_a[FHP_DIR_NW][i];
        uint8_t w  = fhp->dir_a[FHP_DIR_W][i];
        uint8_t sw = fhp->dir_a[FHP_DIR_SW][i];
        uint8_t se = fhp->dir_a[FHP_DIR_SE][i];

        int axis_ew  = e && w;
        int axis_nesw = ne && sw;
        int axis_nwse = nw && se;
        int total = e + ne + nw + w + sw + se;

        uint8_t out_e = e, out_ne = ne, out_nw = nw,
                out_w = w, out_sw = sw, out_se = se;

        if (total == 2 && axis_ew) {
            out_e = out_w = 0;
            if (fhp_rng_bit(fhp)) { out_ne = out_sw = 1; }
            else                  { out_nw = out_se = 1; }
        } else if (total == 2 && axis_nesw) {
            out_ne = out_sw = 0;
            if (fhp_rng_bit(fhp)) { out_e = out_w = 1; }
            else                  { out_nw = out_se = 1; }
        } else if (total == 2 && axis_nwse) {
            out_nw = out_se = 0;
            if (fhp_rng_bit(fhp)) { out_e = out_w = 1; }
            else                  { out_ne = out_sw = 1; }
        } else if (total == 3 && e && nw && sw && !ne && !w && !se) {
            // triplet symetrique A (E, NW, SW a 120 degres) : rotation
            // deterministe de 60 degres vers l'AUTRE triplet symetrique.
            // Sans cette regle, le gaz possede une quantite conservee
            // parasite (en plus de la masse et de la quantite de
            // mouvement) qui peut le figer en rubans/voies stationnaires
            // -- exactement le symptome observe a l'ecran. C'est la
            // regle a 3 corps du FHP-I complet, omise dans la premiere
            // version et documentee comme limitation a l'epoque.
            out_e = out_nw = out_sw = 0;
            out_ne = out_w = out_se = 1;
        } else if (total == 3 && ne && w && se && !e && !nw && !sw) {
            // triplet symetrique B : rotation vers le triplet A.
            out_ne = out_w = out_se = 0;
            out_e = out_nw = out_sw = 1;
        }
        // sinon : inchange (0, 1, ou 3+ particules autres que les deux
        // triplets symetriques, paires non frontales — cas transparents)

        coll[FHP_DIR_E][i]  = out_e;
        coll[FHP_DIR_NE][i] = out_ne;
        coll[FHP_DIR_NW][i] = out_nw;
        coll[FHP_DIR_W][i]  = out_w;
        coll[FHP_DIR_SW][i] = out_sw;
        coll[FHP_DIR_SE][i] = out_se;
    }
}

// Phase 2 — transport. Chaque particule du plan de collision, direction
// d, avance d'UN pas dans cette direction. Ecrit par diffusion (scatter)
// plutot que par lecture (gather) : pour chaque case source, on calcule
// sa destination et on y ecrit — puisque le voisinage hexagonal est une
// bijection sur le tore (chaque case a EXACTEMENT un voisin dans chaque
// direction, et cette relation est inversible), aucune collision
// d'ecriture n'est possible. La conservation du nombre de particules
// EST le test qui verifie cette bijectivite.
static void fhp_transport(FHPState *fhp, uint8_t *coll[6]) {
    size_t n = (size_t)fhp->width * fhp->height;
    for (int d = 0; d < 6; d++) memset(fhp->dir_b[d], 0, n);

    for (uint32_t y = 0; y < fhp->height; y++) {
        for (uint32_t x = 0; x < fhp->width; x++) {
            size_t i = (size_t)y * fhp->width + x;
            for (int d = 0; d < 6; d++) {
                if (!coll[d][i]) continue;
                uint32_t nx, ny;
                if (fhp->open_right_edge) {
                    // bords horizontaux ouverts : une particule qui sort
                    // par la gauche ou la droite disparait simplement
                    // (elle n'est pas ecrite nulle part).
                    if (!fhp_neighbor_open(fhp, x, y, (FHPDirection)d, &nx, &ny))
                        continue;
                } else {
                    fhp_neighbor(fhp, x, y, (FHPDirection)d, &nx, &ny);
                }
                fhp->dir_b[d][ny * fhp->width + nx] = 1;
            }
        }
    }
}

void fhp_step(FHPState *fhp) {
    size_t n = (size_t)fhp->width * fhp->height;
    uint8_t *coll[6];
    for (int d = 0; d < 6; d++) coll[d] = malloc(n);

    fhp_collide(fhp, coll);
    fhp_transport(fhp, coll);

    for (int d = 0; d < 6; d++) {
        free(coll[d]);
        uint8_t *tmp = fhp->dir_a[d];
        fhp->dir_a[d] = fhp->dir_b[d];
        fhp->dir_b[d] = tmp;
    }
}
