#import "CECatalog.h"
#import "../Core/CECore.h"
#import "../Network/CEAPIClient.h"
#import "../Network/CENetworkObserver.h"

@implementation CEConversationRecord @end

@interface CECatalog ()
@property (nonatomic) BOOL refreshing;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CEConversationRecord *> *byID;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSData *> *fullDataByID;
@property (nonatomic, strong) NSDate *lastRefresh;
@end

@implementation CECatalog
+ (instancetype)shared { static CECatalog *v; static dispatch_once_t once; dispatch_once(&once, ^{ v = [CECatalog new]; v.byID = [NSMutableDictionary dictionary]; v.fullDataByID = [NSMutableDictionary dictionary]; }); return v; }

- (void)start {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(templateChanged:) name:CENetworkTemplateDidChangeNotification object:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self refreshIfPossible]; });
}
- (void)templateChanged:(NSNotification *)note { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self refreshIfPossible]; }); }

- (void)refreshIfPossible {
    if (self.refreshing || ![CEAPIClient shared].isReady) return;
    if (self.lastRefresh && [[NSDate date] timeIntervalSinceDate:self.lastRefresh] < 25) return;
    self.refreshing = YES;
    NSMutableDictionary<NSString *, CEConversationRecord *> *fresh = [NSMutableDictionary dictionary];
    [self fetchGlobalPageAtOffset:0 accumulator:fresh completion:^{
        NSArray<NSString *> *projects = [CENetworkObserver shared].knownProjectIDs.allObjects;
        [self fetchProjects:projects index:0 accumulator:fresh completion:^{
            @synchronized (self) {
                for (NSString *cid in fresh) self.byID[cid] = fresh[cid];
                self.lastRefresh = [NSDate date];
                self.refreshing = NO;
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:CECatalogDidChangeNotification object:self];
            CEConversationContext *ctx = [CEConversationContext shared];
            CEConversationRecord *record = ctx.conversationID.length ? [self recordForID:ctx.conversationID] : nil;
            if (record.title.length) [ctx updateTitle:record.title];
        }];
    }];
}

- (NSString *)projectIDFromURL:(NSURL *)url {
    NSString *path = url.path ?: @"";
    static NSRegularExpression *re; static dispatch_once_t once;
    dispatch_once(&once, ^{ re = [NSRegularExpression regularExpressionWithPattern:@"/gizmos/(g-p-[^/]+)/conversations" options:NSRegularExpressionCaseInsensitive error:nil]; });
    NSTextCheckingResult *m = [re firstMatchInString:path options:0 range:NSMakeRange(0, path.length)];
    return m.numberOfRanges > 1 ? [path substringWithRange:[m rangeAtIndex:1]] : nil;
}

- (NSDictionary *)conversationContainerFromObject:(id)object {
    if (![object isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *root = object;
    if ([root[@"mapping"] isKindOfClass:NSDictionary.class] && root[@"current_node"]) return root;
    NSDictionary *conversation = [root[@"conversation"] isKindOfClass:NSDictionary.class] ? root[@"conversation"] : nil;
    if ([conversation[@"mapping"] isKindOfClass:NSDictionary.class] && conversation[@"current_node"]) return conversation;
    return nil;
}

- (void)ingestResponseData:(NSData *)data requestURL:(NSURL *)requestURL {
    if (!data.length) return;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (!root) return;

    NSMutableDictionary<NSString *, CEConversationRecord *> *captured = [NSMutableDictionary dictionary];
    NSString *projectID = [self projectIDFromURL:requestURL];
    [self collectConversationObjects:root forcedProjectID:projectID accumulator:captured depth:0];

    NSDictionary *container = [self conversationContainerFromObject:root];
    NSString *conversationID = CEExtractConversationIDFromString(requestURL.absoluteString ?: @"");
    if (!conversationID.length && [container[@"id"] isKindOfClass:NSString.class]) conversationID = container[@"id"];
    if (!conversationID.length && [container[@"conversation_id"] isKindOfClass:NSString.class]) conversationID = container[@"conversation_id"];
    NSString *fullTitle = [container[@"title"] isKindOfClass:NSString.class] ? [container[@"title"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
    if (conversationID.length && container) {
        CEConversationRecord *record = captured[conversationID] ?: [CEConversationRecord new];
        record.conversationID = conversationID;
        if (fullTitle.length) record.title = fullTitle;
        if (!record.title.length) record.title = @"当前会话";
        captured[conversationID] = record;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL changed = NO;
        @synchronized (self) {
            for (NSString *cid in captured) {
                CEConversationRecord *incoming = captured[cid];
                CEConversationRecord *existing = self.byID[cid];
                if (existing) {
                    if (incoming.title.length && ![incoming.title isEqualToString:@"当前会话"]) existing.title = incoming.title;
                    if (incoming.updatedAt) existing.updatedAt = incoming.updatedAt;
                    if (incoming.projectID.length) existing.projectID = incoming.projectID;
                } else self.byID[cid] = incoming;
                changed = YES;
            }
            if (conversationID.length && container) {
                self.fullDataByID[conversationID] = [data copy];
                changed = YES;
            }
        }
        if (changed) {
            CEConversationContext *ctx = [CEConversationContext shared];
            CEConversationRecord *record = ctx.conversationID.length ? [self recordForID:ctx.conversationID] : nil;
            if (record.title.length && ![record.title isEqualToString:@"当前会话"]) [ctx updateTitle:record.title];
            [[NSNotificationCenter defaultCenter] postNotificationName:CECatalogDidChangeNotification object:self];
        }
    });
}

- (NSData *)conversationDataForID:(NSString *)conversationID { if (!conversationID.length) return nil; @synchronized (self) { return self.fullDataByID[conversationID]; } }

- (void)fetchGlobalPageAtOffset:(NSInteger)offset accumulator:(NSMutableDictionary *)acc completion:(dispatch_block_t)completion {
    if (offset >= 5000) { completion(); return; }
    NSString *path = [NSString stringWithFormat:@"/backend-api/conversations?offset=%ld&limit=100&order=updated", (long)offset];
    [[CEAPIClient shared] getPath:path progress:nil completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (error || !data.length) { completion(); return; }
        NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSArray *items = [root isKindOfClass:NSDictionary.class] ? (root[@"items"] ?: root[@"conversations"] ?: @[]) : @[];
        if (![items isKindOfClass:NSArray.class] || !items.count) { completion(); return; }
        for (id item in items) [self collectConversationObjects:item forcedProjectID:nil accumulator:acc depth:0];
        NSInteger total = [root[@"total"] respondsToSelector:@selector(integerValue)] ? [root[@"total"] integerValue] : 0;
        NSInteger next = offset + items.count;
        if (items.count < 100 || (total > 0 && next >= total)) completion();
        else [self fetchGlobalPageAtOffset:next accumulator:acc completion:completion];
    }];
}

- (void)fetchProjects:(NSArray<NSString *> *)projects index:(NSUInteger)index accumulator:(NSMutableDictionary *)acc completion:(dispatch_block_t)completion {
    if (index >= projects.count) { completion(); return; }
    NSString *projectID = projects[index];
    [self fetchProject:projectID cursor:@"0" pages:0 accumulator:acc completion:^{ [self fetchProjects:projects index:index + 1 accumulator:acc completion:completion]; }];
}

- (void)fetchProject:(NSString *)projectID cursor:(NSString *)cursor pages:(NSUInteger)pages accumulator:(NSMutableDictionary *)acc completion:(dispatch_block_t)completion {
    if (pages >= 60) { completion(); return; }
    NSString *escapedProject = [projectID stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    NSString *escapedCursor = [cursor stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    NSString *path = [NSString stringWithFormat:@"/backend-api/gizmos/%@/conversations?cursor=%@", escapedProject, escapedCursor ?: @"0"];
    [[CEAPIClient shared] getPath:path progress:nil completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (error || !data.length) { completion(); return; }
        NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![root isKindOfClass:NSDictionary.class]) { completion(); return; }
        NSArray *items = root[@"items"] ?: root[@"conversations"] ?: @[];
        for (id item in items) [self collectConversationObjects:item forcedProjectID:projectID accumulator:acc depth:0];
        id rawCursor = root[@"cursor"] ?: root[@"next_cursor"];
        NSString *next = [rawCursor isKindOfClass:NSString.class] ? rawCursor : [rawCursor respondsToSelector:@selector(stringValue)] ? [rawCursor stringValue] : nil;
        if (!items.count || !next.length || [next isEqualToString:cursor]) completion();
        else [self fetchProject:projectID cursor:next pages:pages + 1 accumulator:acc completion:completion];
    }];
}

- (void)collectConversationObjects:(id)value forcedProjectID:(NSString *)projectID accumulator:(NSMutableDictionary *)acc depth:(NSUInteger)depth {
    if (!value || depth > 6) return;
    if ([value isKindOfClass:NSArray.class]) { for (id child in value) [self collectConversationObjects:child forcedProjectID:projectID accumulator:acc depth:depth + 1]; return; }
    if (![value isKindOfClass:NSDictionary.class]) return;
    NSDictionary *d = value;
    NSString *cid = [d[@"id"] isKindOfClass:NSString.class] ? d[@"id"] : [d[@"conversation_id"] isKindOfClass:NSString.class] ? d[@"conversation_id"] : nil;
    NSString *title = [d[@"title"] isKindOfClass:NSString.class] ? d[@"title"] : [d[@"name"] isKindOfClass:NSString.class] ? d[@"name"] : nil;
    if (cid.length && title.length && ![cid hasPrefix:@"g-"]) {
        CEConversationRecord *record = acc[cid] ?: [CEConversationRecord new]; record.conversationID = cid; record.title = title;
        record.projectID = projectID ?: ([d[@"gizmo_id"] isKindOfClass:NSString.class] ? d[@"gizmo_id"] : record.projectID);
        id time = d[@"update_time"] ?: d[@"updated_at"] ?: d[@"updatedAt"] ?: d[@"create_time"];
        if ([time respondsToSelector:@selector(doubleValue)] && [time doubleValue] > 1000000) record.updatedAt = [NSDate dateWithTimeIntervalSince1970:[time doubleValue]];
        acc[cid] = record;
    }
    for (id child in d.allValues) if ([child isKindOfClass:NSDictionary.class] || [child isKindOfClass:NSArray.class]) [self collectConversationObjects:child forcedProjectID:projectID accumulator:acc depth:depth + 1];
}

- (CEConversationRecord *)recordForID:(NSString *)conversationID { if (!conversationID.length) return nil; @synchronized (self) { return self.byID[conversationID]; } }
- (NSArray<CEConversationRecord *> *)recordsMatchingTitle:(NSString *)title {
    if (!title.length) return @[];
    NSMutableArray *out = [NSMutableArray array];
    @synchronized (self) { for (CEConversationRecord *r in self.byID.allValues) if ([r.title isEqualToString:title]) [out addObject:r]; }
    [out sortUsingComparator:^NSComparisonResult(CEConversationRecord *a, CEConversationRecord *b) { return [(b.updatedAt ?: NSDate.distantPast) compare:(a.updatedAt ?: NSDate.distantPast)]; }];
    return out;
}

- (NSArray<CEConversationRecord *> *)candidatesForView:(UIView *)view {
    NSArray<NSString *> *strings = CECollectVisibleStrings(view, 4);
    for (NSString *s in strings) {
        NSString *cid = CEExtractConversationIDFromString(s);
        if (!cid.length) continue;
        CEConversationRecord *record = [self recordForID:cid];
        if (record) return @[record];
        CEConversationRecord *fallback = [CEConversationRecord new]; fallback.conversationID = cid; fallback.title = @"当前会话"; return @[fallback];
    }
    for (NSString *s in strings) { NSArray *matches = [self recordsMatchingTitle:s]; if (matches.count) return matches; }
    return @[];
}

- (void)updateTitle:(NSString *)title forConversationID:(NSString *)conversationID {
    if (!conversationID.length || !title.length) return;
    @synchronized (self) {
        CEConversationRecord *record = self.byID[conversationID];
        if (!record) { record = [CEConversationRecord new]; record.conversationID = conversationID; self.byID[conversationID] = record; }
        record.title = title; record.updatedAt = [NSDate date];
    }
    if ([[CEConversationContext shared].conversationID isEqualToString:conversationID]) [[CEConversationContext shared] updateTitle:title];
    [[NSNotificationCenter defaultCenter] postNotificationName:CECatalogDidChangeNotification object:self];
}
@end
