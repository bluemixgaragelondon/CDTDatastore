//
//  CDTBlobEncryptedData.h
//  CloudantSync
//
//  Created by Enrique de la Torre Fernandez on 21/05/2015.
//  Copyright (c) 2015 IBM Cloudant. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//  http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//

#import <Foundation/Foundation.h>

#import "CDTBlobReader.h"
#import "CDTBlobWriter.h"

#import "CDTEncryptionKey.h"

extern NSString *const CDTBlobEncryptedDataErrorDomain;

typedef NS_ENUM(NSInteger, CDTBlobEncryptedDataError) {
    CDTBlobEncryptedDataErrorFileTooSmall,
    CDTBlobEncryptedDataErrorWrongVersion,
    CDTBlobEncryptedDataErrorNoDataProvided
};

@interface CDTBlobEncryptedData : NSObject <CDTBlobReader, CDTBlobWriter>

- (instancetype)init UNAVAILABLE_ATTRIBUTE;

- (instancetype)initWithPath:(NSString *)path
               encryptionKey:(CDTEncryptionKey *)encryptionKey NS_DESIGNATED_INITIALIZER;

+ (instancetype)blobWithPath:(NSString *)path encryptionKey:(CDTEncryptionKey *)encryptionKey;

@end
