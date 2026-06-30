//
//  cam_core.c
//  cam-8
//
//  Created by Patricia Benedetto on 29/06/2026.
//

#include "cam_core.h"
#include <stdio.h>

CAMState* cam_create(CAMGridSize size) {
    CAMState *cam = calloc(1, sizeof(CAMState));
    if (!cam) return NULL;

    cam->width  = (uint32_t)size;
    cam->height = (uint32_t)size;
    cam->size   = size;

    cam->grid_a = calloc(size * size, sizeof(uint8_t));
    cam->grid_b = calloc(size * size, sizeof(uint8_t));

    if (!cam->grid_a || !cam->grid_b) {
        cam_destroy(cam);
        return NULL;
    }

    return cam;
}

void cam_destroy(CAMState *cam) {
    if (!cam) return;
    free(cam->grid_a);
    free(cam->grid_b);
    free(cam);
}

void cam_swap_buffers(CAMState *cam) {
    uint8_t *tmp = cam->grid_a;
    cam->grid_a  = cam->grid_b;
    cam->grid_b  = tmp;
}
