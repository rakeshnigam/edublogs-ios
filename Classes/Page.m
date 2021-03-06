//
//  Page.m
//  WordPress
//
//  Created by Jorge Bernal on 12/20/10.
//  Copyright 2010 WordPress. All rights reserved.
//

#import "Page.h"
#import "NSMutableDictionary+Helpers.h"

@interface AbstractPost (WordPressApi)
- (NSDictionary *)XMLRPCDictionary;
@end

@interface Page (WordPressApi)
- (NSDictionary *)XMLRPCDictionary;
- (void)postPostWithSuccess:(void (^)())success failure:(void (^)(NSError *error))failure;
- (void)getPostWithSuccess:(void (^)())success failure:(void (^)(NSError *error))failure;
- (void)editPostWithSuccess:(void (^)())success failure:(void (^)(NSError *error))failure;
- (void)deletePostWithSuccess:(void (^)())success failure:(void (^)(NSError *error))failure;
@end

@interface Page (PrivateMethods)
- (void )updateFromDictionary:(NSDictionary *)postInfo;
@end


@implementation Page
@dynamic parentID;

+ (Page *)newPageForBlog:(Blog *)blog {
    Page *page = [[Page alloc] initWithEntity:[NSEntityDescription entityForName:@"Page"
                                                          inManagedObjectContext:[blog managedObjectContext]]
               insertIntoManagedObjectContext:[blog managedObjectContext]];
    
    page.blog = blog;
    
    return page;
}

+ (Page *)newDraftForBlog:(Blog *)blog {
    Page *page = [self newPageForBlog:blog];
    page.dateCreated = [NSDate date];
    page.remoteStatus = AbstractPostRemoteStatusLocal;
    page.status = @"publish";
    [page save];
    
    return page;
}

+ (Page *)findWithBlog:(Blog *)blog andPostID:(NSNumber *)postID {
    NSSet *results = [blog.posts filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"postID == %@",postID]];
    
    if (results && (results.count > 0)) {
        return [[results allObjects] objectAtIndex:0];
    }
    return nil;
}

+ (Page *)createOrReplaceFromDictionary:(NSDictionary *)postInfo forBlog:(Blog *)blog {
    Page *page = [self findWithBlog:blog andPostID:[postInfo objectForKey:@"page_id"]];
    
    if (page == nil) {
        page = [[Page newPageForBlog:blog] autorelease];
    }
	
	[page updateFromDictionary:postInfo];
    return page;
}

+ (NSString *)titleForRemoteStatus:(NSNumber *)remoteStatus {
    if ([remoteStatus intValue] == AbstractPostRemoteStatusSync) {
		return NSLocalizedString(@"Pages", @"");
    } else {
		return [super titleForRemoteStatus:remoteStatus];
	}
}

- (void )updateFromDictionary:(NSDictionary *)postInfo {
	self.postTitle      = [postInfo objectForKey:@"title"];
    self.postID         = [[postInfo objectForKey:@"page_id"] numericValue];
    self.content        = [postInfo objectForKey:@"description"];
    self.date_created_gmt    = [postInfo objectForKey:@"date_created_gmt"];
    self.status         = [postInfo objectForKey:@"page_status"];
    self.password       = [postInfo objectForKey:@"wp_password"];
    self.remoteStatus   = AbstractPostRemoteStatusSync;
	self.permaLink      = [postInfo objectForKey:@"permaLink"];
	self.mt_excerpt		= [postInfo objectForKey:@"mt_excerpt"];
	self.mt_text_more	= [postInfo objectForKey:@"mt_text_more"];
	self.wp_slug		= [postInfo objectForKey:@"wp_slug"];
}

@end

@implementation Page (WordPressApi)

- (NSDictionary *)XMLRPCDictionary {
    NSMutableDictionary *postParams = [NSMutableDictionary dictionaryWithDictionary:[super XMLRPCDictionary]];

    if (self.status == nil)
        self.status = @"publish";

    [postParams setObject:self.status forKey:@"page_status"];
    
    return postParams;
}

- (void)postPostWithSuccess:(void (^)())success failure:(void (^)(NSError *error))failure {
    NSArray *parameters = [self.blog getXMLRPCArgsWithExtra:[self XMLRPCDictionary]];
    self.remoteStatus = AbstractPostRemoteStatusPushing;
    
    [self.blog.api callMethod:@"metaWeblog.newPost"
                   parameters:parameters
                      success:^(AFHTTPRequestOperation *operation, id responseObject) {
                          if ([responseObject respondsToSelector:@selector(numericValue)]) {
                              self.postID = [responseObject numericValue];
                              self.remoteStatus = AbstractPostRemoteStatusSync;
                              [self save];
                              [self getPostWithSuccess:nil failure:nil];
                              if (success) success();
                              [[NSNotificationCenter defaultCenter] postNotificationName:@"PostUploaded" object:self];
                          } else if (failure) {
                              self.remoteStatus = AbstractPostRemoteStatusFailed;
                              NSDictionary *userInfo = [NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Invalid value returned for new post: %@", responseObject] forKey:NSLocalizedDescriptionKey];
                              NSError *error = [NSError errorWithDomain:@"org.edublogs" code:0 userInfo:userInfo];
                              failure(error);
                              [[NSNotificationCenter defaultCenter] postNotificationName:@"PostUploadFailed" object:self];
                          }
                      } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                          self.remoteStatus = AbstractPostRemoteStatusFailed;
                          if (failure) failure(error);
                          [[NSNotificationCenter defaultCenter] postNotificationName:@"PostUploadFailed" object:self];
                      }];    
}

- (void)getPostWithSuccess:(void (^)())success failure:(void (^)(NSError *error))failure {
    NSArray *parameters = [NSArray arrayWithObjects:self.postID, self.blog.username, self.blog.password, nil];
    [self.blog.api callMethod:@"metaWeblog.getPost"
                   parameters:parameters
                      success:^(AFHTTPRequestOperation *operation, id responseObject) {
                          [self updateFromDictionary:responseObject];
                          if (success) success();
                      } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                          if (failure) {
                              failure(error);
                          }
                      }];
}

- (void)editPostWithSuccess:(void (^)())success failure:(void (^)(NSError *error))failure {
    if (self.postID == nil) {
        if (failure) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"Can't edit a post if it's not in the server" forKey:NSLocalizedDescriptionKey];
            NSError *error = [NSError errorWithDomain:@"org.edublogs" code:0 userInfo:userInfo];
            failure(error);
        }
        return;
    }
    
    NSArray *parameters = [NSArray arrayWithObjects:self.postID, self.blog.username, self.blog.password, [self XMLRPCDictionary], nil];
    self.remoteStatus = AbstractPostRemoteStatusPushing;
    [self.blog.api callMethod:@"metaWeblog.editPost"
                   parameters:parameters
                      success:^(AFHTTPRequestOperation *operation, id responseObject) {
                          self.remoteStatus = AbstractPostRemoteStatusSync;
                          if (success) success();
                          [[NSNotificationCenter defaultCenter] postNotificationName:@"PostUploaded" object:self];
                      } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                          self.remoteStatus = AbstractPostRemoteStatusFailed;
                          if (failure) failure(error);
                          [[NSNotificationCenter defaultCenter] postNotificationName:@"PostUploadFailed" object:self];
                      }];
}

- (void)deletePostWithSuccess:(void (^)())success failure:(void (^)(NSError *error))failure {
    if (![self hasRemote]) {
        [[self managedObjectContext] deleteObject:self];
        if (success) success();
        return;
    }
    
    if (self.postID == nil) {
        if (failure) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"Can't delete a post if it's not in the server" forKey:NSLocalizedDescriptionKey];
            NSError *error = [NSError errorWithDomain:@"org.edublogs" code:0 userInfo:userInfo];
            failure(error);
        }
        return;
    }
    
    NSArray *parameters = [NSArray arrayWithObjects:@"unused", self.postID, self.blog.username, self.blog.password, nil];
    [self.blog.api callMethod:@"metaWeblog.deletePost"
                   parameters:parameters
                      success:^(AFHTTPRequestOperation *operation, id responseObject) {
                          [[self managedObjectContext] deleteObject:self];
                          if (success) success();
                      } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                          if (failure) failure(error);
                      }];
}

@end