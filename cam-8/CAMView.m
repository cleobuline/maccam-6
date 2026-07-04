//
//  CAMView.m
//  cam-8
//
//  Created by Patricia Benedetto on 29/06/2026.
//

#import "CAMView.h"

@implementation CAMView {
    CGContextRef    _bitmapContext;
    CGColorSpaceRef _colorSpace;
    uint8_t        *_pixels;      // buffer RGBA
    size_t          _pixelWidth;
    size_t          _pixelHeight;
}

- (void)dealloc {
    [self _teardownContext];
}

- (void)_teardownContext {
    if (_bitmapContext) {
        CGContextRelease(_bitmapContext);
        _bitmapContext = NULL;
    }
    if (_colorSpace) {
        CGColorSpaceRelease(_colorSpace);
        _colorSpace = NULL;
    }
    if (_pixels) {
        free(_pixels);
        _pixels = NULL;
    }
}

- (void)_setupContextForSize:(size_t)size {
    [self _teardownContext];

    _pixelWidth  = size;
    _pixelHeight = size;
    _colorSpace  = CGColorSpaceCreateDeviceRGB();

    size_t bytesPerRow = _pixelWidth * 4; // RGBA
    _pixels = calloc(_pixelHeight * bytesPerRow, 1);

    _bitmapContext = CGBitmapContextCreate(
        _pixels,
        _pixelWidth,
        _pixelHeight,
        8,              // bits per component
        bytesPerRow,
        _colorSpace,
        kCGImageAlphaPremultipliedLast
    );
}

- (void)setCamState:(CAMState *)camState {
    _camState = camState;
    if (camState) {
        [self _setupContextForSize:camState->width];
    }
}

- (void)renderFrame {
    if (!_camState || !_bitmapContext) return;

    uint32_t w = _camState->width;
    uint32_t h = _camState->height;
    int vis = self.palette ? self.palette.visibleMask : 0xF;

    for (uint32_t y = 0; y < h; y++) {
        for (uint32_t x = 0; x < w; x++) {
            uint8_t r, g, b;
            cam_palette((vis & 1) ? _camState->plane0_a[y * w + x] : 0,
                        (vis & 2) ? _camState->plane1_a[y * w + x] : 0,
                        (vis & 4) ? _camState->plane2_a[y * w + x] : 0,
                        (vis & 8) ? _camState->plane3_a[y * w + x] : 0,
                        &r, &g, &b);

            size_t idx = (y * w + x) * 4;
            _pixels[idx + 0] = r;
            _pixels[idx + 1] = g;
            _pixels[idx + 2] = b;
            _pixels[idx + 3] = 255;
        }
    }

    [self setNeedsDisplay:YES];
}

// convertit un point NSView en coordonnées grille
// IMPORTANT : ce calcul doit rester en phase avec squareBounds dans -drawRect:
// (même minDim, même xOffset/yOffset), sinon le pinceau se décale par rapport
// à ce qui est affiché dès que la vue n'est pas carrée.
- (NSPoint)_gridPointFromEvent:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];

    CGFloat minDim  = MIN(self.bounds.size.width, self.bounds.size.height);
    CGFloat xOffset = (self.bounds.size.width  - minDim) / 2.0;
    CGFloat yOffset = (self.bounds.size.height - minDim) / 2.0;

    // width == height pour une grille CAM, donc une seule échelle suffit
    CGFloat scale = _camState->width / minDim;

    CGFloat localX = p.x - xOffset;
    CGFloat localY = p.y - yOffset;

    return NSMakePoint(localX * scale,
                        (_camState->height - 1) - localY * scale);
}

- (void)_paintAtGridX:(int)gx y:(int)gy {
    if (!_camState || !_palette) return;

    int      size  = _palette.brushSize;
    int      plane = _palette.currentPlane;
    CAMTool  tool  = _palette.currentTool;
    uint32_t w     = _camState->width;
    uint32_t h     = _camState->height;

    uint8_t *grids[4] = { _camState->plane0_a, _camState->plane1_a,
                          _camState->plane2_a, _camState->plane3_a };
    uint8_t *grid = grids[plane & 3];
    uint8_t  val  = (tool == CAMToolEraser) ? 0 : 1;

    if (tool == CAMToolPencil || tool == CAMToolEraser) {
        // pinceau carré centré sur gx,gy
        for (int dy = -size/2; dy <= size/2; dy++) {
            for (int dx = -size/2; dx <= size/2; dx++) {
                int nx = gx + dx;
                int ny = gy + dy;
                if (nx >= 0 && nx < (int)w && ny >= 0 && ny < (int)h) {
                    grid[ny * w + nx] = val;
                }
            }
        }
    } else if (tool == CAMToolCircle) {
        // cercle plein centré sur gx,gy de rayon size
        int r = size;
        for (int dy = -r; dy <= r; dy++) {
            for (int dx = -r; dx <= r; dx++) {
                if (dx*dx + dy*dy <= r*r) {
                    int nx = gx + dx;
                    int ny = gy + dy;
                    if (nx >= 0 && nx < (int)w && ny >= 0 && ny < (int)h) {
                        grid[ny * w + nx] = val;
                    }
                }
            }
        }
    } else if (tool == CAMToolSquare) {
        // carré plein centré sur gx,gy de côté size*2
        int r = size;
        for (int dy = -r; dy <= r; dy++) {
            for (int dx = -r; dx <= r; dx++) {
                int nx = gx + dx;
                int ny = gy + dy;
                if (nx >= 0 && nx < (int)w && ny >= 0 && ny < (int)h) {
                    grid[ny * w + nx] = val;
                }
            }
        }
    }

    [self renderFrame];
}

// La grille doit pouvoir prendre le focus clavier : c'est ce qui permet
// à Cmd+V de remonter jusqu'au Document (coller une image) au lieu
// d'être intercepté par l'éditeur de règle.
- (BOOL)acceptsFirstResponder { return YES; }

- (void)mouseDown:(NSEvent *)event {
    [self.window makeFirstResponder:self];
    NSPoint gp = [self _gridPointFromEvent:event];
    [self _paintAtGridX:(int)gp.x y:(int)gp.y];
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint gp = [self _gridPointFromEvent:event];
    [self _paintAtGridX:(int)gp.x y:(int)gp.y];
}

- (void)drawRect:(NSRect)dirtyRect {
    if (!_bitmapContext) return;

    CGImageRef image = CGBitmapContextCreateImage(_bitmapContext);
    if (!image) return;

    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];

    // 1. Calculer un carré parfait centré dans l'espace disponible
    CGFloat minDim = MIN(self.bounds.size.width, self.bounds.size.height);
    CGFloat xOffset = (self.bounds.size.width - minDim) / 2.0;
    CGFloat yOffset = (self.bounds.size.height - minDim) / 2.0;
    CGRect squareBounds = CGRectMake(xOffset, yOffset, minDim, minDim);

    // 2. Désactiver le lissage pour garder des pixels bien nets
    CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);

    CGContextDrawImage(ctx, squareBounds, image);
    CGImageRelease(image);
}

@end
