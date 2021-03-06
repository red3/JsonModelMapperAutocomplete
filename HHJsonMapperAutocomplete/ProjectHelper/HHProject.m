//
//  HHProject.m
//  HHJsonMapperAutocomplete
//
//  Created by Herui on 6/29/16.
//  Copyright © 2016 hirain. All rights reserved.
//

#import "HHProject.h"
#import "HHWorkspaceManager.h"
#import "HHFile.h"
#import "NSString+PDRegex.h"

@implementation HHProject

+ (NSDictionary *)propertyListWithPath:(NSString *)path {
    
    // file content
    NSString *content = [self getFileContent];;
    NSArray *interfaces = getIntefaceNameByContent(content);
    // all propertes
    NSDictionary *properties = getPropertiesByInterfaceName(interfaces, content);
    return properties;
}

+ (NSArray *)fileReferences {
    
    NSArray *projectFiles = [self flattenedProjectContents];
    
    NSMutableArray *references = [NSMutableArray array];
    
    for (PBXReference *pbxReference in projectFiles) {
        
        HHFile *file = [[HHFile alloc] initWithPBXReference:pbxReference];
        if (references) {
            [references addObject:file];
        }
        
    }
    
    return [references copy];
}



+ (NSArray *)flattenedProjectContents {
    NSArray *workspaceReferencedContainers = [[[HHWorkspaceManager currentWorkspace] referencedContainers] allObjects];
    NSArray *contents = [NSArray array];
    
    for (IDEContainer *container in workspaceReferencedContainers) {
        if ([container isKindOfClass:NSClassFromString(@"Xcode3Project")]) {
            Xcode3Project *project = (Xcode3Project *)container;
            Xcode3Group *rootGroup = [project rootGroup];
            PBXGroup *pbxGroup = [rootGroup group];
            
            NSMutableArray *groupContents = [NSMutableArray array];
            [pbxGroup flattenItemsIntoArray:groupContents];
            contents = [contents arrayByAddingObjectsFromArray:groupContents];
        }
    }
    
    return contents;
    
}

//获取文件内容
+ (NSString *)getFileContent {
    
    IDESourceCodeDocument *doc = [HHWorkspaceManager currentSourceCodeDocument];
    if (doc) {
        DVTFilePath *filePath = doc.filePath;
        NSString *fileName = filePath.fileURL.lastPathComponent;
        fileName = [self fileNameByStrippingExtensionAndLastOccuranceOfTest:fileName];
        
        HHFile *headerRef = nil;
        HHFile *sourceRef = nil;
        NSArray *fileReferences = [self fileReferences];
        for (HHFile *reference in fileReferences) {
            if ([reference.name rangeOfString:fileName].location != NSNotFound) {
                if ([reference.name.pathExtension isEqualToString:@"m"]) {
                    sourceRef = reference;
                } else if ([reference.name.pathExtension isEqualToString:@"h"]) {
                    headerRef = reference;
                    
                    NSString *path = reference.absolutePath;
                    NSString *string = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
                    return string;
                }
            }
        }
    }
    
    return nil;
    
}

+ (NSString *)fileNameByStrippingExtensionAndLastOccuranceOfTest:(NSString *)fileName {
    NSString *file = [fileName stringByDeletingPathExtension];
    NSString *strippedFileName = nil;
    
    if (file.length >= 5) {
        NSRange rangeOfOccurrenceOfTest = [file rangeOfString:@"Test" options:NSCaseInsensitiveSearch range:NSMakeRange(file.length - 5, 5)];
        
        NSRange rangeOfOccurrenceOfSpec = [file rangeOfString:@"Spec" options:NSCaseInsensitiveSearch range:NSMakeRange(file.length - 5, 5)];
        if (rangeOfOccurrenceOfTest.location != NSNotFound) {
            strippedFileName = [file substringToIndex:rangeOfOccurrenceOfTest.location];
        } else if (rangeOfOccurrenceOfSpec.location != NSNotFound) {
            strippedFileName = [file substringToIndex:rangeOfOccurrenceOfSpec.location];
        } else {
            strippedFileName = file;
        }
    } else {
        strippedFileName = file;
    }
    
    return strippedFileName;
}

NSArray *getIntefaceNameByContent(NSString *content) {
    
    NSArray *res = [content hh_stringsByExtractingGroupsUsingRegexPattern:@"(@interface\\s*\\S*)"];
    
    NSMutableArray *results = @[].mutableCopy;
    for (NSString *test in res) {
        NSString *bullet = [[test componentsSeparatedByString:@" "] lastObject];
        [results addObject:bullet];
    }
    
    return [results copy];
}

NSDictionary *getPropertiesByInterfaceName(NSArray *interfaces, NSString *content) {
    
    NSMutableDictionary *propertyDics = @{}.mutableCopy;
    
    for (int i=0; i<interfaces.count; i++) {
        
        NSString *interfaceName = interfaces[i];
        NSString *regex;
        // @interface\s+JsonModelA([\s\S]*)?JsonModelB
        if (i+1 < interfaces.count) {
            NSString *nextInterfaceName = interfaces[i+1];
            regex = [NSString stringWithFormat:@"@interface\\s+%@([\\s\\S]*)?%@", interfaceName, nextInterfaceName];
        } else {
            regex = [NSString stringWithFormat:@"@interface\\s+%@([\\s\\S]*)?@end", interfaceName];
        }
        
        NSArray *interfaceContents = [content hh_stringsByExtractingGroupsUsingRegexPattern:regex];
        if (!interfaceContents) {
            return nil;
        }
       
        NSString *interfaceContent = interfaceContents[0];
        
        regex = [NSString stringWithFormat:@"@interface\\s+%@(?s)(.*)@end", interfaceName];
        
        
        NSArray *res = [interfaceContent hh_stringsByExtractingGroupsUsingRegexPattern:regex];
        for (NSString *test in res) {
            // 匹配property
            NSArray *properties = [test hh_stringsByExtractingGroupsUsingRegexPattern:@"@property.*?;"];
            
            NSMutableArray *array = [NSMutableArray array];
            
            for (NSString *subString in properties) {
                NSRange lastStarRange = [subString rangeOfString:@"*" options:NSBackwardsSearch];
                NSRange lastSpaceRange = [subString rangeOfString:@" " options:NSBackwardsSearch];
                
                NSString *str;
                if (lastSpaceRange.location > lastStarRange.location || lastStarRange.length == 0) {
                    str = [subString substringWithRange:NSMakeRange(lastSpaceRange.location, subString.length - lastSpaceRange.location)];
                } else {
                    str = [subString substringWithRange:NSMakeRange(lastStarRange.location, subString.length - lastStarRange.location)];
                }
                NSMutableCharacterSet *set = [[NSMutableCharacterSet alloc] init];
                [set addCharactersInString:@" *;"];
                //去掉空格和逗号
                NSMutableArray *strArr = [[str componentsSeparatedByCharactersInSet:set] mutableCopy];
                [strArr removeObject:@" "];
                str = [strArr componentsJoinedByString:@""];
                
                [array addObject:str];
            }
            [propertyDics setObject:array forKey:interfaceName];
        }


    }
    return [propertyDics copy];

}






@end
