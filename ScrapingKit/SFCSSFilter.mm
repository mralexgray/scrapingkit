//  Copyright (c) 2013 segfault.jp. All rights reserved.

#import "SFDocument.h"
#import "SFCSSSelectorParser.h"

#include <ctype.h>
#include <objc/runtime.h>

static NSRegularExpression *const RX_N_EQUATION = //     12      3        4
[NSRegularExpression regularExpressionWithPattern:@"^\\s*(([-+]?)(\\d*)n)?((?:(?<=n)(?>[-+]\\d+)?|(?:[-+]?\\d+)?))"
                                          options:0 error:NULL];

static NSRegularExpression *const RX_EQ_ODD =
[NSRegularExpression regularExpressionWithPattern:@"^\\s*odd"
                                          options:NSRegularExpressionCaseInsensitive
                                            error:NULL];

static NSRegularExpression *const RX_EQ_EVEN =
[NSRegularExpression regularExpressionWithPattern:@"^\\s*even"
                                          options:NSRegularExpressionCaseInsensitive
                                            error:NULL];

static NSRegularExpression *const RX_MATCHES_OF =
[NSRegularExpression regularExpressionWithPattern:@"^\\s*of"
                                          options:NSRegularExpressionCaseInsensitive
                                            error:NULL];

static NSRegularExpression *const RX_COMMA_SEPARATOR =
[NSRegularExpression regularExpressionWithPattern:@"^\\s*,"
                                          options:0 error:NULL];


@implementation SFCSSFilter
- (BOOL)match:(SFElement*)elem
      context:(SFElement*)context
{
    return true;
}

- (NSString*)dump { return @"*"; }

- (NSString*)description
{
    NSMutableString *buf = NSMutableString.string;
    for (auto head = self; head; head = head->next) {
        [buf appendString:head.dump];
    }
    return buf;
}

@end


@implementation SFUserFilter

+ (void)initialize
{
    if(self != SFUserFilter.class) {
        [SFCSSSelectorParser addFilter:[self filterIdByClass:class_getName(self)] with:
         ^SFCSSFilter*(id)
         {
             return [[self alloc] init];
         }];
    }
}

+ (NSString*)filterIdByClass:(const char*)name
{
    // クラス名から動的にフィルター名を作る
    const char *p = name;
    while(*p) { // 接頭子っぽいのは除去
        char c = *p;
        if(!isupper(c)) {
            if(p - name >= 3) {
                name = p - 1;
            }
            else if(islower(c) && isupper(p[1])) {
                name = p + 1;
            }
            break;
        }
        ++p;
    }
    NSMutableString *buf = [[NSMutableString alloc] init];
    while(*name) { // キャメルケースっぽいのを判定
        char c = *name++;
        if(isupper(c)) {
            c = tolower(c);
            if(islower(*name) && buf.length) {
                [buf appendFormat:@"-%c%c", c, *name++];
                continue;
            }
        }
        [buf appendFormat:@"%c", c];
    }
    if([buf hasSuffix:@"-filter"]) {
        return [buf substringToIndex:buf.length - 7];
    }
    return buf;
}

- (NSString*)dump
{
    return [NSString stringWithFormat:@":%@"
            , [SFUserFilter filterIdByClass:class_getName(self.class)]];
}

@end


@implementation SFTypeSelector
{
    NSString *_name;
}

- (id)initWithName:(NSString*)name
{
    if((self = [self init])) {
        self->_name = name.lowercaseString;
    }
    return self;
}

- (BOOL)match:(SFElement*)elem
      context:(SFElement*)context
{
    return [_name isEqualToString:@"*"]
        || [_name isEqualToString:elem.name];
}

- (NSString*)dump { return _name; }
@end


@implementation SFAttributeFilter
{
    NSString *_name;
    NSString *_data;
    enum MatchType _type;
}

- (id)initWithName:(NSString*)name
          withData:(NSString*)data
          withKind:(enum MatchType)kind
{
    if((self = [self init])) {
        self->_name = name;
        self->_data = data;
        self->_type = kind;
    }
    return self;
}

- (BOOL)match:(SFElement*)elem
      context:(SFElement*)context
{
    NSString *data = [elem get:_name];
    if(!data) {
        return NO;
    }
    switch(_type) {
        case MATCH_EQUAL:
            return [data isEqualToString:_data];
        case MATCH_EQUAL_PART:
        {
            NSRange range = [data rangeOfString:_data];
            int pos = range.location;
            int end = range.location + range.length;
            return pos != NSNotFound
            && (pos == 0           || [data characterAtIndex:pos-1] == ' ')
            && (end == data.length || [data characterAtIndex:end  ] == ' ');
        }
        case MATCH_PREFIX: return [data hasPrefix:_data];
        case MATCH_SUFFIX: return [data hasSuffix:_data];
        case MATCH_SUBSTR:
            return [data rangeOfString:_data].location != NSNotFound;
    }
    return NO;
}

- (NSString*)dump
{
    return [NSString stringWithFormat:@"[%@%s='%@']",
        _name,
        _type == MATCH_EQUAL_PART ? "~":
        _type == MATCH_PREFIX     ? "^":
        _type == MATCH_SUFFIX     ? "$":
        _type == MATCH_SUBSTR     ? "*":
        "",
        _data];
}
@end


@implementation SFNEquation
{
    int _scale;
    int _base;
}

+ (SFNEquation*)parse:(SFCSSSelectorParser*)parser
{
    if ([parser scan:RX_EQ_EVEN]) return [[self alloc] initWithScale:2 withBase:0];
    if ([parser scan:RX_EQ_ODD ]) return [[self alloc] initWithScale:2 withBase:1];
    if (![parser scan:RX_N_EQUATION]) {
        return nil;
    }
    int scale = 0;
    if ([parser $:1].length) {
        auto sig = [parser $:2]; // [+-]?
        auto num = [parser $:3]; // \d+
        scale = ([@"-" isEqual:sig] ? -1: 1) * (num.length ? num.intValue: 1);
    }
    return [[self alloc] initWithScale:scale withBase:[parser $:4].intValue];
}

- (id)initWithScale:(int)scale withBase:(int)base
{
    if((self = [self init])) {
        self->_scale = scale;
        self->_base  = base;
    }
    return self;
}

- (BOOL)test:(int)n
{
    int min = _scale >= 0 ? _base: INT_MIN;
    int max = _scale <= 0 ? _base: INT_MAX;
    if (!(min <= n && n <= max)) {
        return NO;
    }
    n -= _base;
    return (_scale ? n % _scale: n) == 0;
}

- (NSString*)description
{
    return [NSString stringWithFormat:@"%dn%+d", _scale, _base];
}

@end


@implementation SFNEquationFilter
{
    enum EquationKind _kind;
    SFNEquation *_eq;
}

+ (void)initialize
{

    [SFCSSSelectorParser addFilter:@"nth-child"
                              with:^SFCSSFilter*(SFCSSSelectorParser *parser)
    { return [self parse:parser withKind:NTH_CHILD]; }];
    
    [SFCSSSelectorParser addFilter:@"nth-last-child"
                              with:^SFCSSFilter*(SFCSSSelectorParser *parser)
     { return [self parse:parser withKind:NTH_CHILD_REV]; }];
    
    [SFCSSSelectorParser addFilter:@"nth-of-type"
                              with:^SFCSSFilter*(SFCSSSelectorParser *parser)
     { return [self parse:parser withKind:NTH_OF_TYPE]; }];
    
    [SFCSSSelectorParser addFilter:@"nth-last-of-type"
                              with:^SFCSSFilter*(SFCSSSelectorParser *parser)
     { return [self parse:parser withKind:NTH_OF_TYPE_REV]; }];
    
    [SFCSSSelectorParser addFilter:@"first-child"
                              with:^SFCSSFilter*(id)
     { return [[self alloc] initWithKind:NTH_CHILD withEquation:
               [[SFNEquation alloc] initWithScale:0 withBase:0]]; }];
    
    [SFCSSSelectorParser addFilter:@"last-child"
                              with:^SFCSSFilter*(id)
     { return [[self alloc] initWithKind:NTH_CHILD_REV withEquation:
               [[SFNEquation alloc] initWithScale:0 withBase:0]]; }];

}

+ (SFNEquationFilter*)parse:(SFCSSSelectorParser*)parser
                   withKind:(enum EquationKind)kind
{
    SFNEquation *eq = [SFNEquation parse:parser];
    if (!eq) {
        [parser raiseError:[NSString stringWithFormat:
                @"nth-* must be followed by valid expression."]];
    }
    return [[self alloc] initWithKind:kind withEquation:eq];
}

- (id)initWithKind:(enum EquationKind)kind withEquation:(SFNEquation*)eq
{
    if((self = [self init])) {
        self->_kind = kind;
        self->_eq   = eq;
    }
    return self;
}

- (BOOL)match:(SFElement*)elem
      context:(SFElement*)context
{
    return [_eq test:
            _kind == NTH_OF_TYPE     ? elem.typeIndex     :
            _kind == NTH_OF_TYPE_REV ? elem.lastTypeIndex :
            _kind == NTH_CHILD       ? elem.nodeIndex     :
            _kind == NTH_CHILD_REV   ? elem.lastNodeIndex : 0];
}

- (NSString*)dump
{
    return [NSString stringWithFormat:@":nth-%@(%@)",
            _kind == NTH_OF_TYPE     ? @      "of-type" :
            _kind == NTH_OF_TYPE_REV ? @ "last-of-type" :
            _kind == NTH_CHILD       ? @        "child" :
            _kind == NTH_CHILD_REV   ? @   "last-child" : nil, _eq];
}

@end


@implementation SFNotFilter
{
    SFCSSFilter *_filter;
}

+ (void)initialize
{
    [SFCSSSelectorParser addFilter:@"not" with:^SFCSSFilter*(SFCSSSelectorParser *parser)
    {
        return [[self alloc] initWithFilter:[parser parseSelector]];
    }];
}

- (id)initWithFilter:(SFCSSFilter*)filter
{
    if((self = [self init])) {
        self->_filter = filter;
    }
    return self;
}

- (BOOL)match:(SFElement*)elem
      context:(SFElement*)context
{
    for (SFCSSFilter *cur = _filter; cur; cur = cur->next) {
        if (![cur match:elem context:context]) {
            return YES;
        }
    }
    return NO;
}

- (NSString*)dump
{
    return [NSString stringWithFormat:@":not(%@)", _filter];
}
@end


@implementation SFMatchesAnyFilter
{
    NSArray *_filters;
}

+ (void)initialize
{
    [SFCSSSelectorParser addFilter:@"matches" with:^SFCSSFilter*(SFCSSSelectorParser *parser)
     {
         NSMutableArray *a = NSMutableArray.array;
         do {
             auto next = [parser parseSelector];
             if (!next) {
                 [parser raiseError:@"Expected SIMPLE_SELECTOR, but not found!"];
             }
             [a addObject:next];
         } while ([parser scan:RX_COMMA_SEPARATOR]);
         return [[self alloc] initWithFilters:a];
     }];
}

- (id)initWithFilters:(NSArray*)filters
{
    if((self = [self init])) {
        self->_filters = filters;
    }
    return self;
}

- (BOOL)match:(SFElement*)elem
      context:(SFElement*)context
{
    for (SFCSSFilter *e in _filters) {
        for (SFCSSFilter *cur = e; cur; cur = cur->next) {
            if (![cur match:elem context:context]) {
                goto next;
            }
        }
        return YES;
    next:;
    }
    return NO;
}

- (NSString*)dump
{
    NSMutableString *buf = NSMutableString.string;
    for(SFCSSFilter *head in _filters) {
        if(buf.length)
        [buf appendString:@", "];
        [buf appendString:head.description];
    }
    return [NSString stringWithFormat:@":matches(%@)", buf];
}
@end


@implementation SFOnlyChildFilter
- (BOOL)match:(SFElement*)elem
      context:(SFElement*)context
{
    return elem == elem.parent.firstElement && elem.nextElement == nil;
}
@end


@implementation SFOnlyOfTypeFilter
- (BOOL)match:(SFElement*)elem
      context:(SFElement*)context
{
    return elem.typeIndex == elem.lastTypeIndex;
}
@end


@implementation SFBaseFilter
- (BOOL)match:(SFElement*)elem
      context:(SFElement*)context
{
    return elem == context;
}
@end


@implementation SFRootFilter
- (BOOL)match:(SFElement*)elem
      context:(SFElement*)context
{
    return [elem.parent isMemberOfClass:[SFDocument class]];
}
@end


@implementation SFEmptyFilter
- (BOOL)match:(SFElement*)elem
      context:(SFElement*)context
{
    return elem.first == nil;
}
@end


@implementation SFBlankFilter
- (BOOL)match:(SFElement*)elem
      context:(SFElement*)context
{
    for (auto e = elem.first; e; e = e.next) {
        if (!([e isKindOfClass:SFText.class] && ((SFText*) e).isBlank)) {
            return NO;
        }
    }
    return YES;
}
@end


@implementation SFNthMatchFilter
{
    BOOL _last;
    SFNEquation *_eq;
    SFCSSFilter *_filter;
}

+ (void)initialize
{

    [SFCSSSelectorParser addFilter:@"nth-match"
                              with:^SFCSSFilter*(SFCSSSelectorParser *parser)
     { return [self parse:parser withLast:NO]; }];
    
    [SFCSSSelectorParser addFilter:@"nth-last-match"
                              with:^SFCSSFilter*(SFCSSSelectorParser *parser)
     { return [self parse:parser withLast:YES]; }];

}

+ (SFNEquationFilter*)parse:(SFCSSSelectorParser*)parser withLast:(BOOL)b
{
    SFNEquation *eq = [SFNEquation parse:parser];
    if (!eq) {
        [parser raiseError:@"nth-[last-]match must be followed by valid expression."];
    }
    if (![parser scan:RX_MATCHES_OF]) {
        [parser raiseError:@"Expected 'of', but not found."];
    }
    return [[self alloc] initWithLast:b
                         withEquation:eq
                         withSelector:[parser parseSelector]];
}

- (id)initWithLast:(BOOL)b
      withEquation:(SFNEquation*)eq
      withSelector:(SFCSSFilter*)filter
{
    if((self = [self init])) {
        self->_last   = b;
        self->_eq     = eq;
        self->_filter = filter;
    }
    return self;
}

- (BOOL)match:(SFElement*)elem
      context:(SFElement*)context
{
    return NO;
}

@end
