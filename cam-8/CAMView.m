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

    // converti chaque cellule uint8 en pixel RGBA niveaux de gris
    for (uint32_t y = 0; y < h; y++) {
        for (uint32_t x = 0; x < w; x++) {
            uint8_t val = cam_get(_camState, x, y);
            size_t  idx = (y * w + x) * 4;
            _pixels[idx + 0] = val;   // R
            _pixels[idx + 1] = val;   // G
            _pixels[idx + 2] = val;   // B
            _pixels[idx + 3] = 255;   // A
        }
    }

    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    if (!_bitmapContext) return;

    CGImageRef image = CGBitmapContextCreateImage(_bitmapContext);
    if (!image) return;

    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    CGRect bounds = CGRectMake(0, 0, self.bounds.size.width,
                                     self.bounds.size.height);
    CGContextDrawImage(ctx, bounds, image);
    CGImageRelease(image);
}

@end
