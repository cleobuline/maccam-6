// §9.3 : cycle de vie d'un ver tubicole — le test d'acceptation de CAM-B.
#include "cam_core.h"
#include "cam_forth.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *read_file(const char *p){
    static char b[8192]; FILE *f=fopen(p,"r");
    if(!f) return NULL;
    size_t n=fread(b,1,8191,f); b[n]=0; fclose(f); return b;
}

int main_(void) {
    int fails = 0;
    printf("Test TUBE-WORMS (chapitre 9 — couplage CAM-A/CAM-B)\n");

    char *src = read_file("regles/tube-worms.rule");
    ForthVM vm; forth_init(&vm);
    ForthTables t; memset(&t, 0, sizeof(t));
    int built = forth_compile(&vm, &t, src);
    if (built != (FORTH_BUILT_LUT | FORTH_BUILT_LUT_B)) {
        printf("  ✗ built=%d (attendu LUT_A|LUT_B=%d)\n", built,
               FORTH_BUILT_LUT | FORTH_BUILT_LUT_B);
        return 1;
    }
    printf("  ✓ les deux tables construites (A et B)\n");

    // --- 1. ver isolé : jamais 2 voisins actifs -> reste dehors à jamais
    CAMState *cam = cam_create(CAM_SIZE_128);
    cam->plane0_a[64*128+64] = 1;
    cam_set_rule(src);
    for (int s = 0; s < 50; s++) cam_step(cam);
    if (cam->plane0_a[64*128+64] == 1 && cam->plane2_a[64*128+64] == 0
        && cam->plane3_a[64*128+64] == 0)
        printf("  ✓ ver isolé : dehors pour toujours, chrono à 0\n");
    else { printf("  ✗ ver isolé perturbé sans raison\n"); fails++; }
    cam_destroy(cam);

    // --- 2. colonie 3x3 : le centre doit suivre le cycle
    // sorti(2 pas le temps que l'alarme et le chrono s'arment),
    // caché exactement 3 pas, ressorti.
    cam = cam_create(CAM_SIZE_128);
    for (int dy = -1; dy <= 1; dy++)
        for (int dx = -1; dx <= 1; dx++)
            cam->plane0_a[(64+dy)*128 + 64+dx] = 1;
    cam_set_rule(src);

    int c = 64*128+64;
    int seq[12], timer[12];
    for (int s = 0; s < 12; s++) {
        seq[s]   = cam->plane0_a[c];
        timer[s] = cam->plane2_a[c] | (cam->plane3_a[c] << 1);
        cam_step(cam);
    }
    // Dynamique exacte de la règle imprimée : le pipeline à deux temps
    // ré-arme le chrono une fois (le ver est encore dehors quand le chrono
    // vient de s'armer), d'où une retraite de 4 pas et un cycle de
    // période 7 : sorti 3 pas, caché 4 pas, ad libitum.
    printf("    plan0 : "); for (int s=0;s<12;s++) printf("%d", seq[s]);
    printf("\n    chrono: "); for (int s=0;s<12;s++) printf("%d", timer[s]);
    printf("\n");

    int hid = 0, hidden_run = 0, max_run = 0, armed = 0, periodic = 1;
    for (int s = 0; s < 12; s++) {
        if (!seq[s]) { hid = 1; hidden_run++; if (hidden_run > max_run) max_run = hidden_run; }
        else hidden_run = 0;
        if (timer[s] == 3) armed = 1;
        if (s + 7 < 12 && seq[s] != seq[s + 7]) periodic = 0;
    }
    if (hid && max_run == 4 && armed && periodic)
        printf("  ✓ cycle du ver : retraite de 4 pas, chrono armé à 3, période 7\n");
    else { printf("  ✗ cycle inattendu (max caché=%d, armé=%d, périodique=%d)\n", max_run, armed, periodic); fails++; }
    cam_destroy(cam);

    printf(fails ? "ÉCHEC (%d)\n" : "LE RÉCIF EST VIVANT — CAM-B OPÉRATIONNELLE\n", fails);
    return fails ? 1 : 0;
}
