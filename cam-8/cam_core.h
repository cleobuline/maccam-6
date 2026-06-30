//
//  cam_core.h
//  cam-8
//
//  Created by Patricia Benedetto on 29/06/2026.
//


#ifndef CAM8_CORE_H
#define CAM8_CORE_H

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef enum {
    CAM_SIZE_128  = 128,
    CAM_SIZE_256  = 256,
    CAM_SIZE_512  = 512,
    CAM_SIZE_1024 = 1024
} CAMGridSize;

typedef struct {
    uint8_t  *grid_a;   // buffer courant
    uint8_t  *grid_b;   // buffer suivant
    uint32_t  width;
    uint32_t  height;
    CAMGridSize size;
} CAMState;

CAMState* cam_create(CAMGridSize size);
void      cam_destroy(CAMState *cam);
void      cam_swap_buffers(CAMState *cam);

// accès inline à une cellule
static inline uint8_t cam_get(const CAMState *cam, int x, int y) {
    return cam->grid_a[y * cam->width + x];
}

static inline void cam_set(CAMState *cam, int x, int y, uint8_t val) {
    cam->grid_b[y * cam->width + x] = val;
}

#endif /* CAM8_CORE_H */
