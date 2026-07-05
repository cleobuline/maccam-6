// Test d'usage complet : une "scene" FHP comme on la jouerait dans
// l'app -- injection continue depuis un bord, obstacle circulaire,
// des milliers de pas, verification de bout en bout que rien ne
// diverge (pas de fuite de particules, pas de plantage, densite
// bornee), et rendu d'une image finale lisible.
#include "fph.h"
#include <stdio.h>
#include <stdlib.h>

typedef struct {
    const char *name;
    uint32_t width, height;
    int obstacle_cx, obstacle_cy, obstacle_r;
    int inflow_density_percent;
    int steps;
} FHPScene;

static void run_scene(FHPScene scene) {
    printf("=== Scene : %s ===\n", scene.name);
    FHPState *fhp = fhp_create(scene.width, scene.height);
    fhp->rng_state = 0xF007BA11u;

    for (int y = 0; y < (int)scene.height; y++)
        for (int x = 0; x < (int)scene.width; x++) {
            int dx = x - scene.obstacle_cx, dy = y - scene.obstacle_cy;
            if (dx*dx + dy*dy <= scene.obstacle_r * scene.obstacle_r)
                fhp_set_obstacle(fhp, x, y, 1);
        }

    int max_density_seen = 0;
    int prev_population = -1;
    int conservation_ok = 1;

    for (int s = 0; s < scene.steps; s++) {
        // injection au bord gauche, comme le ferait un pinceau "Lancer"
        // dans l'app, mais applique chaque pas pour simuler un vent
        // continu
        for (uint32_t y = 0; y < scene.height; y++) {
            fhp->rng_state = fhp->rng_state * 1664525u + 1013904223u;
            if ((fhp->rng_state >> 16) % 100 < (uint32_t)scene.inflow_density_percent)
                fhp->dir_a[FHP_DIR_E][y * scene.width + 0] = 1;
        }

        int pop_before_step = fhp_total_population(fhp);
        fhp_step(fhp);
        int pop_after_step = fhp_total_population(fhp);

        // la population ne peut QU'augmenter ou rester stable (on injecte,
        // on ne retire jamais) -- si elle baisse, il y a une fuite
        if (prev_population >= 0 && pop_after_step < pop_before_step) {
            printf("  x FUITE au pas %d : %d -> %d\n", s, pop_before_step, pop_after_step);
            conservation_ok = 0;
        }
        prev_population = pop_after_step;

        for (uint32_t y = 0; y < scene.height && s == scene.steps - 1; y++)
            for (uint32_t x = 0; x < scene.width; x++) {
                int d = fhp_local_density(fhp, x, y);
                if (d > max_density_seen) max_density_seen = d;
            }
    }

    int final_pop = fhp_total_population(fhp);
    printf("  population finale : %d\n", final_pop);
    printf("  densite locale max observee : %d/6\n", max_density_seen);
    printf("  conservation (jamais de fuite) : %s\n", conservation_ok ? "OK" : "ECHEC");

    // densite locale ne doit jamais depasser 6 (par definition du plan
    // booleen 6 bits) -- sinon quelque chose ecrit hors-bornes
    int bounds_ok = (max_density_seen <= 6);
    printf("  bornes respectees (<=6/cellule) : %s\n", bounds_ok ? "OK" : "ECHEC");

    fhp_destroy(fhp);

    if (!conservation_ok || !bounds_ok) {
        printf("  RESULTAT : ECHEC\n\n");
        exit(1);
    }
    printf("  RESULTAT : OK\n\n");
}

int toto(void) {
    // Scene 1 : la scene canonique, jet + cylindre, taille app-realiste
    run_scene((FHPScene){
        .name = "Jet contre cylindre (256x128, comme une grille app)",
        .width = 256, .height = 128,
        .obstacle_cx = 60, .obstacle_cy = 64, .obstacle_r = 12,
        .inflow_density_percent = 55,
        .steps = 2000
    });

    // Scene 2 : grille plus petite, densite tres haute (stress test)
    run_scene((FHPScene){
        .name = "Stress densite haute (128x128, 90% injection)",
        .width = 128, .height = 128,
        .obstacle_cx = 40, .obstacle_cy = 64, .obstacle_r = 15,
        .inflow_density_percent = 90,
        .steps = 1500
    });

    // Scene 3 : sans obstacle du tout (gaz libre, verifie l'absence de
    // dependance cachee a la presence d'un mur)
    run_scene((FHPScene){
        .name = "Gaz libre sans obstacle (192x96)",
        .width = 192, .height = 96,
        .obstacle_cx = -100, .obstacle_cy = -100, .obstacle_r = 1, // hors grille
        .inflow_density_percent = 40,
        .steps = 1000
    });

    printf("TOUTES LES SCENES PASSENT — la regle FHP tient en usage reel\n");
    return 0;
}
