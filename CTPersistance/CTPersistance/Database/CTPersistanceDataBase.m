//
//  CTPersistanceDataBase.m
//  CTPersistance
//
//  Created by casa on 15/10/4.
//  Copyright © 2015年 casa. All rights reserved.
//

#import "CTPersistanceDataBase.h"
#import "CTPersistanceConfiguration.h"
#import "CTPersistanceMigrator.h"
#import "NSString+ReqularExpression.h"

@interface CTPersistanceDataBase ()

@property (nonatomic, assign) sqlite3 *database;
@property (nonatomic, copy) NSString *databaseName;
@property (nonatomic, copy) NSString *databaseFilePath;
@property (nonatomic, strong) CTPersistanceMigrator *migrator;

@end

@implementation CTPersistanceDataBase

#pragma mark - life cycle
- (instancetype)initWithDatabaseName:(NSString *)databaseName error:(NSError *__autoreleasing *)error
{
    self = [super init];
    if (self) {
        self.databaseName = databaseName;
        self.databaseFilePath = [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:databaseName];

        BOOL isFileExists = [[NSFileManager defaultManager] fileExistsAtPath:self.databaseFilePath];

        const char *path = [self.databaseFilePath UTF8String];
        int result = sqlite3_open_v2(path, &_database,
                                     SQLITE_OPEN_CREATE |
                                     SQLITE_OPEN_READWRITE |
                                     SQLITE_OPEN_FULLMUTEX |
                                     SQLITE_OPEN_SHAREDCACHE,
                                     NULL);

        if (result != SQLITE_OK) {
            if (error) {
                CTPersistanceErrorCode errorCode = CTPersistanceErrorCodeOpenError;
                NSString *sqliteErrorString = [NSString stringWithCString:sqlite3_errmsg(self.database) encoding:NSUTF8StringEncoding];
                NSString *errorString = [NSString stringWithFormat:@"open database at %@ failed with error:\n %@", self.databaseFilePath, sqliteErrorString];
                if (isFileExists == NO) {
                    errorCode = CTPersistanceErrorCodeCreateError;
                    errorString = [NSString stringWithFormat:@"create database at %@ failed with error:\n %@", self.databaseFilePath, [NSString stringWithCString:sqlite3_errmsg(self.database) encoding:NSUTF8StringEncoding]];
                }
                
                *error = [NSError errorWithDomain:kCTPersistanceErrorDomain code:errorCode userInfo:@{NSLocalizedDescriptionKey:errorString}];
            }
            return nil;
        }
        
        if (isFileExists == NO) {
            [self.migrator createVersionTableWithDatabase:self];
        } else {
            if ([self.migrator databaseShouldMigrate:self]) {
                [self.migrator databasePerformMigrate:self];
            }
        }
    }
    return self;
}

- (void)dealloc
{
    [self closeDatabase];
}

#pragma mark - public methods
- (void)closeDatabase
{
    sqlite3_close_v2(self.database);
    self.database = 0x00;
    self.databaseFilePath = nil;
}

#pragma mark - getters and setters
- (CTPersistanceMigrator *)migrator
{
    if (_migrator == nil) {
        NSString *persistanceConfigurationPlistPath = [[NSBundle mainBundle] pathForResource:kCTPersisatanceConfigurationFileName ofType:@"plist"];
        NSDictionary *persistanceConfigurationPlist = [NSDictionary dictionaryWithContentsOfFile:persistanceConfigurationPlistPath];
        __block Class migratorClass = NULL;
        [persistanceConfigurationPlist enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull pattern, NSString * _Nonnull migartorClassName, BOOL * _Nonnull stop) {
            if ([self.databaseName isMatchWithRegularExpression:pattern]) {
                migratorClass = NSClassFromString(migartorClassName);
            }
        }];
        if (migratorClass == NULL) {
            NSException *exception = [NSException exceptionWithName:@"Create Migrator Error" reason:[NSString stringWithFormat:@"Can't find DatabaseName[%@] matches in PListFile[%@] which content is :\n %@ \n", self.databaseName, persistanceConfigurationPlistPath, persistanceConfigurationPlist] userInfo:nil];
            @throw exception;
        }
        _migrator = [[migratorClass alloc] init];
    }
    return _migrator;
}

@end
