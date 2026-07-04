// Test du voisinage Margolus dans CAM-FORTH.
// Vérifie que les règles du livre (BBM §18.2, SWAP-ON-DIAG §12.4)
// écrites en Forth avec CENTER/CW/CCW/OPP produisent les bonnes tables.
#include "cam_forth.h"
#include <stdio.h>
#include <string.h>

// --- copies locales des générateurs de référence de cam_core.c ---
static int popcount4(uint8_t n) {
    int c = 0;
    for (int i = 0; i < 4; i++) if (n & (1 << i)) c++;
    return c;
}

static void build_bbm_ref(uint8_t table[16]) {
    // Table 18.1 du livre : entrées 0-2 et la dernière = HPP-GAS.
    //  - 1 particule → elle se propage vers son coin opposé (comme SWAP-ON-DIAG)
    //  - 2 particules sur une diagonale → collision, rotation vers l'autre diagonale
    //  - paires adjacentes, 3 et 4 particules → inchangé (miroirs / blocs pleins)
    for (int in = 0; in < 16; in++) table[in] = (uint8_t)in;
    table[1 << 0] = 1 << 3; // NW → SE
    table[1 << 1] = 1 << 2; // NE → SW
    table[1 << 2] = 1 << 1; // SW → NE
    table[1 << 3] = 1 << 0; // SE → NW
    uint8_t d1 = (1 << 0) | (1 << 3); // NW+SE
    uint8_t d2 = (1 << 1) | (1 << 2); // NE+SW
    table[d1] = d2;
    table[d2] = d1;
}

static void build_swap_on_diag_ref(uint8_t table[16]) {
    // chaque cellule prend la valeur de son opposé : NW<->SE, NE<->SW
    for (int in = 0; in < 16; in++) {
        uint8_t nw = (in >> 0) & 1, ne = (in >> 1) & 1;
        uint8_t sw = (in >> 2) & 1, se = (in >> 3) & 1;
        table[in] = (uint8_t)(se | (sw << 1) | (ne << 2) | (nw << 3));
    }
}

static int compare_tables(const char *name, const uint8_t *got, const uint8_t *ref) {
    int fails = 0;
    for (int i = 0; i < 16; i++) {
        if (got[i] != ref[i]) {
            printf("  ✗ %s: entrée %2d : attendu %2d, obtenu %2d\n", name, i, ref[i], got[i]);
            fails++;
        }
    }
    if (!fails) printf("  ✓ %s : 16/16 entrées identiques à la référence\n", name);
    return fails;
}

int main_(void) {
    int total_fails = 0;

    // ---------------------------------------------------------------
    // Test 1 : SWAP-ON-DIAG (§12.4 du livre) : ": SWAP-ON-DIAG OPP ;"
    // ---------------------------------------------------------------
    printf("Test 1 — SWAP-ON-DIAG (OPP pur)\n");
    {
        const char *src =
            ": SWAP-ON-DIAG OPP ;\n"
            "MAKE-TABLE-MARGOLUS SWAP-ON-DIAG\n";

        ForthVM vm;
        forth_init(&vm);
        ForthTables t; memset(&t, 0, sizeof(t));
        int built = forth_compile(&vm, &t, src);

        if (built != FORTH_BUILT_MARGOLUS) {
            printf("  ✗ built = %d (attendu FORTH_BUILT_MARGOLUS=%d)\n", built, FORTH_BUILT_MARGOLUS);
            total_fails++;
        }
        uint8_t ref[16]; build_swap_on_diag_ref(ref);
        total_fails += compare_tables("SWAP-ON-DIAG", t.margolus_p0, ref);
    }

    // ---------------------------------------------------------------
    // Test 2 : BBM, transcription fidèle du §18.2 :
    //   : 2PART  CENTER OPP = IF CW ELSE CENTER THEN ;
    //   : BBM    CENTER CW CCW OPP + + +  { U OPP 2PART U U } ;
    //   (U = CENTER, "unchanged")
    // ---------------------------------------------------------------
    printf("Test 2 — BBM (règle du livre, §18.2)\n");
    {
        const char *src =
            ": 2PART CENTER OPP = IF CW ELSE CENTER THEN ;\n"
            ": BBM\n"
            "  CENTER CW CCW OPP + + +\n"
            "  { 99 0 0 0 99 } DROP\n" // placeholder, remplacé ci-dessous
            ";\n";
        (void)src;

        // La vraie règle : la table inline sélectionne selon le nombre de
        // particules. Problème : { U OPP 2PART U U } du livre contient des
        // MOTS dans la table, pas des littéraux — notre { } n'accepte que
        // des nombres. On transcrit donc via IF/ELSE imbriqués, strictement
        // équivalent :
        const char *src2 =
            ": 2PART CENTER OPP = IF CW ELSE CENTER THEN ;\n"
            ": NPART CENTER CW CCW OPP + + + ;\n"
            ": BBM\n"
            "  NPART 1 = IF OPP ELSE\n"
            "  NPART 2 = IF 2PART ELSE\n"
            "  CENTER\n"
            "  THEN THEN ;\n"
            "MAKE-TABLE-MARGOLUS BBM\n";

        ForthVM vm;
        forth_init(&vm);
        ForthTables t; memset(&t, 0, sizeof(t));
        int built = forth_compile(&vm, &t, src2);

        if (!(built & FORTH_BUILT_MARGOLUS)) {
            printf("  ✗ built = %d, table Margolus non construite\n", built);
            total_fails++;
        }
        uint8_t ref[16]; build_bbm_ref(ref);
        total_fails += compare_tables("BBM", t.margolus_p0, ref);
    }

    // ---------------------------------------------------------------
    // Test 3 : source mixte — une LUT Moore ET une table Margolus dans
    // le même fichier ; les deux doivent être construites.
    // ---------------------------------------------------------------
    printf("Test 3 — source mixte (MAKE-TABLE + MAKE-TABLE-MARGOLUS)\n");
    {
        const char *src =
            ": PARITY NORTH SOUTH XOR EAST WEST XOR XOR ;\n"
            ": SWAPD OPP ;\n"
            "MAKE-TABLE PARITY\n"
            "MAKE-TABLE-MARGOLUS SWAPD\n";

        ForthVM vm;
        forth_init(&vm);
        ForthTables t; memset(&t, 0, sizeof(t));
        int built = forth_compile(&vm, &t, src);

        if (built != (FORTH_BUILT_LUT | FORTH_BUILT_MARGOLUS)) {
            printf("  ✗ built = %d (attendu %d)\n", built, FORTH_BUILT_LUT | FORTH_BUILT_MARGOLUS);
            total_fails++;
        } else {
            printf("  ✓ les deux tables construites (built=%d)\n", built);
        }

        // vérif ponctuelle de la LUT parity : entrée avec NORTH=1 seul → 1
        uint32_t e_north = (1u << 2);
        if ((t.lut[e_north] & 1) != 1) { printf("  ✗ LUT[NORTH]=%d\n", t.lut[e_north]); total_fails++; }
        else printf("  ✓ LUT Moore cohérente (spot check)\n");

        uint8_t ref[16]; build_swap_on_diag_ref(ref);
        total_fails += compare_tables("SWAPD", t.margolus_p0, ref);
    }

    // ---------------------------------------------------------------
    // Test 4 : buffer NULL — MAKE-TABLE-MARGOLUS avec margolus_table==NULL
    // ne doit ni crasher ni prétendre avoir construit quoi que ce soit.
    // ---------------------------------------------------------------
    printf("Test 4 — robustesse buffer NULL\n");
    {
        const char *src = ": R OPP ;\nMAKE-TABLE-MARGOLUS R\n";
        ForthVM vm;
        forth_init(&vm);
        int built = forth_compile(&vm, NULL, src);
        if (built != 0) { printf("  ✗ built=%d (attendu 0)\n", built); total_fails++; }
        else printf("  ✓ pas de crash, built=0\n");
    }

    // ---------------------------------------------------------------
    // Test 5 : syntaxe VERBATIM du livre (§18.2) — table inline avec
    // des mots (U, OPP, 2PART) et >PLN0. Doit produire la même table
    // que la version IF/ELSE du test 2.
    // ---------------------------------------------------------------
    printf("Test 5 — BBM verbatim du livre ({ U OPP 2PART U U } >PLN0)\n");
    {
        const char *src =
            ": 2PART CENTER OPP = IF CW ELSE CENTER THEN ;\n"
            ": BBM\n"
            "  CENTER CW CCW OPP + + +\n"
            "  { U OPP 2PART U U } >PLN0 ;\n"
            "MAKE-TABLE-MARGOLUS BBM\n";

        ForthVM vm;
        forth_init(&vm);
        ForthTables t; memset(&t, 0, sizeof(t));
        int built = forth_compile(&vm, &t, src);

        if (!(built & FORTH_BUILT_MARGOLUS)) {
            printf("  ✗ built = %d, table Margolus non construite\n", built);
            total_fails++;
        }
        uint8_t ref[16]; build_bbm_ref(ref);
        total_fails += compare_tables("BBM-verbatim", t.margolus_p0, ref);
    }

    // ---------------------------------------------------------------
    // Test 6 : rétrocompatibilité — table inline de littéraux purs
    // (comme la règle LIFE de Patricia avec { 0 0 0 1 1 0 0 0 0 }).
    // ---------------------------------------------------------------
    printf("Test 6 — table inline de littéraux (rétrocompatibilité LIFE)\n");
    {
        const char *src =
            ": 8SUM NORTH SOUTH WEST EAST N.WEST N.EAST S.WEST S.EAST + + + + + + + ;\n"
            ": LIFE CENTER 0 = IF 8SUM { 0 0 0 1 0 0 0 0 0 } ELSE 8SUM { 0 0 1 1 0 0 0 0 0 } THEN ;\n"
            "MAKE-TABLE LIFE\n";

        ForthVM vm;
        forth_init(&vm);
        ForthTables t; memset(&t, 0, sizeof(t));
        int built = forth_compile(&vm, &t, src);

        if (!(built & FORTH_BUILT_LUT)) {
            printf("  ✗ built = %d, LUT non construite\n", built);
            total_fails++;
        } else {
            // spot checks Conway : mort + 3 voisins → naît ; vivant + 2 → survit ;
            // vivant + 4 → meurt ; mort + 2 → reste mort.
            // bits: center=0, N=2 S=3 E=4 W=5 NE=6 NW=7 SE=8 SW=9
            uint32_t dead3  = (1u<<2)|(1u<<3)|(1u<<4);          // 3 voisins, mort
            uint32_t live2  = 1u | (1u<<2)|(1u<<3);             // vivant, 2 voisins
            uint32_t live4  = 1u | (1u<<2)|(1u<<3)|(1u<<4)|(1u<<5);
            uint32_t dead2  = (1u<<2)|(1u<<3);
            int ok = ((t.lut[dead3]&1)==1) && ((t.lut[live2]&1)==1) && ((t.lut[live4]&1)==0) && ((t.lut[dead2]&1)==0);
            if (ok) printf("  ✓ LIFE : naissances/survies/morts conformes à Conway\n");
            else { printf("  ✗ LIFE : spot checks échoués (%d %d %d %d)\n",
                          t.lut[dead3]&1, t.lut[live2]&1, t.lut[live4]&1, t.lut[dead2]&1); total_fails++; }
        }
    }

    // ---------------------------------------------------------------
    // Test 7 : syntaxe du vrai CAM Forth — N/MARG puis MAKE-TABLE.
    // La même source rebascule ensuite en N/MOORE pour une LUT : les
    // deux tables doivent être construites, chacune par le bon chemin.
    // ---------------------------------------------------------------
    printf("Test 7 — déclarations N/MARG et N/MOORE (dispatch de MAKE-TABLE)\n");
    {
        const char *src =
            "N/MARG\n"
            ": SWAPD OPP ;\n"
            "MAKE-TABLE SWAPD\n"
            "N/MOORE\n"
            ": PARITY NORTH SOUTH XOR EAST WEST XOR XOR ;\n"
            "MAKE-TABLE PARITY\n";

        ForthVM vm;
        forth_init(&vm);
        ForthTables t; memset(&t, 0, sizeof(t));
        int built = forth_compile(&vm, &t, src);

        if (built != (FORTH_BUILT_LUT | FORTH_BUILT_MARGOLUS)) {
            printf("  ✗ built = %d (attendu %d)\n", built, FORTH_BUILT_LUT | FORTH_BUILT_MARGOLUS);
            total_fails++;
        } else {
            printf("  ✓ N/MARG → table Margolus, N/MOORE → LUT (built=3)\n");
        }

        uint8_t ref[16]; build_swap_on_diag_ref(ref);
        total_fails += compare_tables("SWAPD via N/MARG", t.margolus_p0, ref);

        uint32_t e_north = (1u << 2);
        if ((t.lut[e_north] & 1) != 1) { printf("  ✗ LUT[NORTH]=%d\n", t.lut[e_north]); total_fails++; }
        else printf("  ✓ LUT via N/MOORE cohérente (spot check)\n");
    }

    // ---------------------------------------------------------------
    // Test 8 : expédition par plan en LUT — ": R NORTH >PLN0 EAST >PLN1 ;"
    // doit donner bit0 = NORTH et bit1 = EAST. Et une règle SANS >PLN1
    // doit garder l'ECHO (bit1 = CENTER) par défaut.
    // ---------------------------------------------------------------
    printf("Test 8 — >PLN0 / >PLN1 en LUT, et écho par défaut\n");
    {
        const char *src =
            ": R NORTH >PLN0 EAST >PLN1 ;\n"
            "MAKE-TABLE R\n";

        ForthVM vm;
        forth_init(&vm);
        ForthTables t; memset(&t, 0, sizeof(t));
        int built = forth_compile(&vm, &t, src);

        int fails = 0;
        if (!(built & FORTH_BUILT_LUT)) { printf("  ✗ LUT non construite\n"); fails++; }
        for (uint32_t e = 0; e < FORTH_LUT_SIZE && fails < 4; e++) {
            uint8_t north = (e >> 2) & 1;
            uint8_t east  = (e >> 4) & 1;
            uint8_t expect = north | (east << 1);
            if (t.lut[e] != expect) {
                printf("  ✗ entrée %u : attendu %d, obtenu %d\n", e, expect, t.lut[e]);
                fails++;
            }
        }
        if (!fails) printf("  ✓ bit0=NORTH, bit1=EAST sur les 1024 entrées\n");
        total_fails += fails;

        // écho par défaut : règle sans >PLN1
        const char *src2 = ": R2 NORTH ;\nMAKE-TABLE R2\n";
        ForthVM vm2; forth_init(&vm2);
        ForthTables t2; memset(&t2, 0, sizeof(t2));
        forth_compile(&vm2, &t2, src2);
        int echo_ok = 1;
        for (uint32_t e = 0; e < FORTH_LUT_SIZE; e++) {
            uint8_t center = e & 1;
            if (((t2.lut[e] >> 1) & 1) != center) { echo_ok = 0; break; }
        }
        if (echo_ok) printf("  ✓ sans >PLN1 : bit1 = ECHO (CENTER) partout\n");
        else { printf("  ✗ écho par défaut cassé\n"); total_fails++; }
    }

    // ---------------------------------------------------------------
    // Test 9 : >PLN1 en Margolus — ": T OPP >PLN0 CENTER CW OR >PLN1 ;"
    // p0 = SWAP-ON-DIAG, p1 = OR du centre et de son voisin horaire.
    // Et une règle sans >PLN1 doit laisser margolus_p1_used à 0.
    // ---------------------------------------------------------------
    printf("Test 9 — >PLN1 en Margolus (double table de bloc)\n");
    {
        const char *src =
            "N/MARG\n"
            ": T OPP >PLN0 CENTER CW OR >PLN1 ;\n"
            "MAKE-TABLE T\n";

        ForthVM vm;
        forth_init(&vm);
        ForthTables t; memset(&t, 0, sizeof(t));
        int built = forth_compile(&vm, &t, src);

        int fails = 0;
        if (!(built & FORTH_BUILT_MARGOLUS)) { printf("  ✗ table non construite\n"); fails++; }
        if (!t.margolus_p1_used) { printf("  ✗ margolus_p1_used devrait être 1\n"); fails++; }

        uint8_t ref0[16]; build_swap_on_diag_ref(ref0);
        fails += compare_tables("p0 (OPP)", t.margolus_p0, ref0);

        // p1 attendu : pour chaque coin c, bit = center(c) | cw(c)
        // sens horaire NW->NE->SE->SW : cw(NW)=NE, cw(NE)=SE, cw(SW)=NW, cw(SE)=SW
        int p1_ok = 1;
        for (int in = 0; in < 16; in++) {
            uint8_t nw=in&1, ne=(in>>1)&1, sw=(in>>2)&1, se=(in>>3)&1;
            uint8_t expect = (uint8_t)((nw|ne) | ((ne|se)<<1) | ((sw|nw)<<2) | ((se|sw)<<3));
            if (t.margolus_p1[in] != expect) {
                printf("  ✗ p1 entrée %d : attendu %d, obtenu %d\n", in, expect, t.margolus_p1[in]);
                p1_ok = 0; fails++;
            }
        }
        if (p1_ok) printf("  ✓ p1 (CENTER CW OR) : 16/16 conformes\n");

        // règle sans >PLN1 : p1_used doit rester 0
        const char *src2 = "N/MARG\n: S OPP ;\nMAKE-TABLE S\n";
        ForthVM vm2; forth_init(&vm2);
        ForthTables t2; memset(&t2, 0, sizeof(t2));
        forth_compile(&vm2, &t2, src2);
        if (t2.margolus_p1_used == 0) printf("  ✓ sans >PLN1 : plan 1 en passage inchangé\n");
        else { printf("  ✗ p1_used devrait être 0\n"); fails++; }

        total_fails += fails;
    }

    // ---------------------------------------------------------------
    // Test 10 : PHASE (N/MARG-PH) — ROT-CW/CCW verbatim du §12.7 :
    //   PHASE { CCW CW } >PLN0
    // phase 0 : chaque cellule copie son CCW → le bloc tourne horaire.
    // phase 1 : chaque cellule copie son CW  → le bloc tourne anti-horaire.
    // ---------------------------------------------------------------
    printf("Test 10 — PHASE / ROT-CW-CCW (§12.7, verbatim)\n");
    {
        const char *src =
            "N/MARG-PH\n"
            ": ROT-CW/CCW PHASE { CCW CW } >PLN0 ;\n"
            "MAKE-TABLE ROT-CW/CCW\n";

        ForthVM vm;
        forth_init(&vm);
        ForthTables t; memset(&t, 0, sizeof(t));
        int built = forth_compile(&vm, &t, src);

        int fails = 0;
        if (!(built & FORTH_BUILT_MARGOLUS)) { printf("  ✗ table non construite\n"); fails++; }

        for (int in = 0; in < 16 && fails < 5; in++) {
            uint8_t nw=in&1, ne=(in>>1)&1, sw=(in>>2)&1, se=(in>>3)&1;
            // phase 0 : out = CCW de chaque coin (ccw: NW<-SW, NE<-NW, SW<-SE, SE<-NE)
            uint8_t exp0 = (uint8_t)(sw | (nw<<1) | (se<<2) | (ne<<3));
            // phase 1 : out = CW de chaque coin (cw: NW<-NE, NE<-SE, SW<-NW, SE<-SW)
            uint8_t exp1 = (uint8_t)(ne | (se<<1) | (nw<<2) | (sw<<3));
            if (t.margolus_p0[in] != exp0) {
                printf("  ✗ phase0 entrée %d : attendu %d, obtenu %d\n", in, exp0, t.margolus_p0[in]); fails++;
            }
            if (t.margolus_p0[in | (1<<8)] != exp1) {
                printf("  ✗ phase1 entrée %d : attendu %d, obtenu %d\n", in, exp1, t.margolus_p0[in | (1<<8)]); fails++;
            }
        }
        // indépendance vis-à-vis du plan 1 (la règle ne lit pas les primés)
        if (t.margolus_p0[5 | (9<<4)] != t.margolus_p0[5]) {
            printf("  ✗ la table dépend du plan 1 alors que la règle ne le lit pas\n"); fails++;
        }
        if (!fails) printf("  ✓ rotation CW en phase 0, CCW en phase 1, indépendante du plan 1\n");
        total_fails += fails;
    }

    // ---------------------------------------------------------------
    // Test 11 : voisins primés Margolus — ": X OPP' >PLN0 CENTER' >PLN1 ;"
    // p0 = rotation 180° du bloc du PLAN 1, p1 = copie du bloc du plan 1.
    // ---------------------------------------------------------------
    printf("Test 11 — voisins primés CW'/CCW'/OPP'/CENTER' (bloc du plan 1)\n");
    {
        const char *src =
            "N/MARG\n"
            ": X OPP' >PLN0 CENTER' >PLN1 ;\n"
            "MAKE-TABLE X\n";

        ForthVM vm;
        forth_init(&vm);
        ForthTables t; memset(&t, 0, sizeof(t));
        int built = forth_compile(&vm, &t, src);

        int fails = 0;
        if (!(built & FORTH_BUILT_MARGOLUS)) { printf("  ✗ table non construite\n"); fails++; }
        if (!t.margolus_p1_used) { printf("  ✗ p1_used devrait être 1\n"); fails++; }

        for (int p1n = 0; p1n < 16 && fails < 5; p1n++) {
            for (int p0n = 0; p0n < 16; p0n += 5) { // p0 ne doit avoir aucun effet
                uint32_t idx = (uint32_t)(p0n | (p1n << 4));
                uint8_t nw=p1n&1, ne=(p1n>>1)&1, sw=(p1n>>2)&1, se=(p1n>>3)&1;
                uint8_t exp_p0 = (uint8_t)(se | (sw<<1) | (ne<<2) | (nw<<3)); // rot180 du plan 1
                if (t.margolus_p0[idx] != exp_p0) {
                    printf("  ✗ p0[%u] : attendu %d, obtenu %d\n", idx, exp_p0, t.margolus_p0[idx]); fails++;
                }
                if (t.margolus_p1[idx] != (uint8_t)p1n) {
                    printf("  ✗ p1[%u] : attendu %d, obtenu %d\n", idx, p1n, t.margolus_p1[idx]); fails++;
                }
            }
        }
        if (!fails) printf("  ✓ OPP' et CENTER' lisent bien le bloc du plan 1\n");
        total_fails += fails;
    }

    // ---------------------------------------------------------------
    // Test 12 : N/VONN — ": P NORTH' SOUTH' XOR EAST WEST XOR XOR ;"
    // encodage : bit2=EAST' bit3=WEST' bit4=SOUTH' bit5=NORTH' bit6=EAST bit7=WEST
    // ---------------------------------------------------------------
    printf("Test 12 — voisinage N/VONN (voisins primés von Neumann)\n");
    {
        const char *src =
            "N/VONN\n"
            ": P NORTH' SOUTH' XOR EAST WEST XOR XOR ;\n"
            "MAKE-TABLE P\n";

        ForthVM vm;
        forth_init(&vm);
        ForthTables t; memset(&t, 0, sizeof(t));
        int built = forth_compile(&vm, &t, src);

        int fails = 0;
        if (!(built & FORTH_BUILT_LUT)) { printf("  ✗ LUT non construite\n"); fails++; }
        if (t.lut_neighborhood != FORTH_NEIGHBORHOOD_VONN) {
            printf("  ✗ lut_neighborhood = %d (attendu VONN)\n", t.lut_neighborhood); fails++;
        }
        for (uint32_t e = 0; e < FORTH_LUT_SIZE && fails < 5; e++) {
            uint8_t north_p = (e >> 5) & 1, south_p = (e >> 4) & 1;
            uint8_t east = (e >> 6) & 1, west = (e >> 7) & 1;
            uint8_t exp = (north_p ^ south_p) ^ (east ^ west);
            if ((t.lut[e] & 1) != exp) {
                printf("  ✗ entrée %u : attendu %d, obtenu %d\n", e, exp, t.lut[e] & 1); fails++;
            }
        }
        if (!fails) printf("  ✓ parité NORTH'/SOUTH'/EAST/WEST correcte sur 1024 entrées\n");
        total_fails += fails;
    }

    printf("\n%s (%d échec%s)\n",
           total_fails ? "ÉCHEC" : "TOUS LES TESTS PASSENT",
           total_fails, total_fails > 1 ? "s" : "");
    return total_fails ? 1 : 0;
}
