#pragma once

#import <Foundation/Foundation.h>

typedef struct { BOOL main, shared; } SGWGImageMatch;
SGWGImageMatch SGWGMatchImage(const char *path);
