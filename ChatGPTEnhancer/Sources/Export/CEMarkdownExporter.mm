#import "CEMarkdownExporter.h"
#import "../Core/CECore.h"

@implementation CEMarkdownExporter

+ (NSString *)normalizedText:(NSString *)value {
    if (![value isKindOfClass:NSString.class]) return @"";
    NSString *text = [value stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    static NSRegularExpression *privateToken; static NSRegularExpression *spaces; static dispatch_once_t once;
    dispatch_once(&once, ^{
        privateToken = [NSRegularExpression regularExpressionWithPattern:@"[^]+" options:0 error:nil];
        spaces = [NSRegularExpression regularExpressionWithPattern:@"\n[ \t]+|[ \t]+\n|\n{3,}" options:0 error:nil];
    });
    text = [privateToken stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@""];
    text = [spaces stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@"\n\n"];
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

+ (NSString *)textFromPart:(id)part {
    if ([part isKindOfClass:NSString.class]) return part;
    if (![part isKindOfClass:NSDictionary.class]) return @"";
    NSDictionary *d = part;
    for (NSString *key in @[@"text", @"content", @"transcript"]) if ([d[key] isKindOfClass:NSString.class]) return d[key];
    if ([d[@"content_type"] isEqual:@"image_asset_pointer"] || d[@"asset_pointer"]) return @"[图片]";
    return @"";
}

+ (NSString *)textFromMessage:(NSDictionary *)message {
    NSDictionary *content = [message[@"content"] isKindOfClass:NSDictionary.class] ? message[@"content"] : @{};
    NSMutableArray<NSString *> *pieces = [NSMutableArray array];
    NSArray *parts = [content[@"parts"] isKindOfClass:NSArray.class] ? content[@"parts"] : @[];
    for (id part in parts) { NSString *v = [self textFromPart:part]; if (v.length) [pieces addObject:v]; }
    if (!pieces.count && [content[@"text"] isKindOfClass:NSString.class]) [pieces addObject:content[@"text"]];
    return [self normalizedText:[pieces componentsJoinedByString:@"\n"]];
}

+ (void)scanSources:(id)value depth:(NSUInteger)depth seen:(NSMutableSet<NSString *> *)seen output:(NSMutableArray<NSDictionary *> *)output {
    if (!value || depth > 4) return;
    if ([value isKindOfClass:NSArray.class]) { for (id child in value) [self scanSources:child depth:depth + 1 seen:seen output:output]; return; }
    if (![value isKindOfClass:NSDictionary.class]) return;
    NSDictionary *d = value;
    NSString *url = [d[@"url"] isKindOfClass:NSString.class] ? d[@"url"] : nil;
    NSString *title = [d[@"title"] isKindOfClass:NSString.class] ? d[@"title"] : nil;
    if (([url hasPrefix:@"http://"] || [url hasPrefix:@"https://"]) && ![seen containsObject:url]) {
        [seen addObject:url]; [output addObject:@{@"url":url, @"title":title.length ? title : url}];
    }
    for (id child in d.allValues) if ([child isKindOfClass:NSDictionary.class] || [child isKindOfClass:NSArray.class]) [self scanSources:child depth:depth + 1 seen:seen output:output];
}

+ (NSArray<NSDictionary *> *)sourcesFromMessage:(NSDictionary *)message {
    NSDictionary *metadata = [message[@"metadata"] isKindOfClass:NSDictionary.class] ? message[@"metadata"] : @{};
    NSMutableArray *out = [NSMutableArray array]; NSMutableSet *seen = [NSMutableSet set];
    for (NSString *key in @[@"content_references", @"citations", @"sources"]) [self scanSources:metadata[key] depth:0 seen:seen output:out];
    return out;
}

+ (NSString *)renderNode:(NSDictionary *)node {
    NSDictionary *message = [node[@"message"] isKindOfClass:NSDictionary.class] ? node[@"message"] : nil;
    if (!message) return @"";
    NSDictionary *author = [message[@"author"] isKindOfClass:NSDictionary.class] ? message[@"author"] : @{};
    NSString *role = [author[@"role"] isKindOfClass:NSString.class] ? author[@"role"] : @"";
    if (![role isEqualToString:@"user"] && ![role isEqualToString:@"assistant"]) return @"";
    NSString *text = [self textFromMessage:message]; if (!text.length) return @"";
    NSMutableString *out = [NSMutableString stringWithFormat:@"## %@\n\n%@", [role isEqualToString:@"user"] ? @"User" : @"Assistant", text];
    NSArray *sources = [self sourcesFromMessage:message];
    if (sources.count) {
        [out appendString:@"\n\n### Sources\n\n"];
        for (NSDictionary *source in sources) {
            NSString *title = [source[@"title"] stringByReplacingOccurrencesOfString:@"]" withString:@"\\]"];
            [out appendFormat:@"- [%@](%@)\n", title, source[@"url"]];
        }
        while ([out hasSuffix:@"\n"]) [out deleteCharactersInRange:NSMakeRange(out.length - 1, 1)];
    }
    return out;
}

+ (NSString *)markdownFromConversationData:(NSData *)data fallbackTitle:(NSString *)fallbackTitle error:(NSError **)error {
    id rootObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![rootObject isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *root = rootObject;
    NSDictionary *container = [root[@"mapping"] isKindOfClass:NSDictionary.class] ? root : ([root[@"conversation"] isKindOfClass:NSDictionary.class] ? root[@"conversation"] : nil);
    NSDictionary *mapping = [container[@"mapping"] isKindOfClass:NSDictionary.class] ? container[@"mapping"] : nil;
    NSString *current = [container[@"current_node"] isKindOfClass:NSString.class] ? container[@"current_node"] : nil;
    if (!mapping || !current.length) {
        if (error) *error = [NSError errorWithDomain:@"ChatGPTEnhancer" code:-50 userInfo:@{NSLocalizedDescriptionKey:@"完整会话结构无法识别。"}];
        return nil;
    }
    NSMutableArray<NSString *> *reverse = [NSMutableArray array]; NSMutableSet *visited = [NSMutableSet set]; NSString *cursor = current;
    while (cursor.length && mapping[cursor] && ![visited containsObject:cursor]) {
        [visited addObject:cursor]; [reverse addObject:cursor];
        NSDictionary *node = [mapping[cursor] isKindOfClass:NSDictionary.class] ? mapping[cursor] : @{};
        cursor = [node[@"parent"] isKindOfClass:NSString.class] ? node[@"parent"] : nil;
    }
    NSArray *path = reverse.reverseObjectEnumerator.allObjects;
    NSMutableArray<NSString *> *messages = [NSMutableArray array];
    for (NSString *nodeID in path) { NSString *rendered = [self renderNode:mapping[nodeID]]; if (rendered.length) [messages addObject:rendered]; }
    if (!messages.count) {
        if (error) *error = [NSError errorWithDomain:@"ChatGPTEnhancer" code:-51 userInfo:@{NSLocalizedDescriptionKey:@"完整会话中没有可导出的用户/助手消息。"}];
        return nil;
    }
    NSString *title = [container[@"title"] isKindOfClass:NSString.class] ? [self normalizedText:container[@"title"]] : @"";
    if (!title.length) title = fallbackTitle.length ? fallbackTitle : @"ChatGPT Conversation";
    return [NSString stringWithFormat:@"# %@\n\n%@\n", title, [messages componentsJoinedByString:@"\n\n---\n\n"]];
}

+ (NSURL *)writeMarkdown:(NSString *)markdown filename:(NSString *)filename error:(NSError **)error {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ChatGPTEnhancerExports"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *safe = CESanitizeFilename(filename); if (![safe.lowercaseString hasSuffix:@".md"]) safe = [safe stringByAppendingString:@".md"];
    NSURL *url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:safe]];
    if (![markdown writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:error]) return nil;
    return url;
}
@end
