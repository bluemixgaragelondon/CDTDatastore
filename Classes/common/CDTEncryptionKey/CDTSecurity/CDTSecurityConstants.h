//
//  CDTSecurityConstants.h
//
//
//  Created by Enrique de la Torre Fernandez on 20/03/2015.
//
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

#warning Is it duplicated?
extern int const CDTkChosenCipherKeySize;

#warning Is it duplicated?
extern int const CDTkChosenCipherIVSize;

extern NSString *const CDTDATASTORE_SECURITY_BASE64_REGEX;

extern NSString *const CDTDATASTORE_SECURITY_DEFAULT_ACCOUNT;

extern int const CDTDATASTORE_SECURITY_DEFAULT_DPK_SIZE;
extern int const CDTDATASTORE_SECURITY_DEFAULT_IV_SIZE;
extern int const CDTDATASTORE_SECURITY_DEFAULT_PBKDF2_ITERATIONS;

extern NSString *const CDTDATASTORE_SECURITY_ERROR_LABEL;
extern NSString *const CDTDATASTORE_SECURITY_ERROR_LABEL_KEYGEN;
extern NSString *const CDTDATASTORE_SECURITY_ERROR_LABEL_ENCRYPT;
extern NSString *const CDTDATASTORE_SECURITY_ERROR_LABEL_DECRYPT;

extern NSString *const CDTDATASTORE_SECURITY_ERROR_MSG_EMPTY_TEXT;
extern NSString *const CDTDATASTORE_SECURITY_ERROR_MSG_EMPTY_KEY;
extern NSString *const CDTDATASTORE_SECURITY_ERROR_MSG_EMPTY_IV;
extern NSString *const CDTDATASTORE_SECURITY_ERROR_MSG_INVALID_ITERATIONS;
extern NSString *const CDTDATASTORE_SECURITY_ERROR_MSG_EMPTY_PASSWORD;
extern NSString *const CDTDATASTORE_SECURITY_ERROR_MSG_EMPTY_SALT;
extern NSString *const CDTDATASTORE_SECURITY_ERROR_MSG_EMPTY_CIPHER;

extern NSString *const CDTDATASTORE_SECURITY_KEY_DPK;
extern NSString *const CDTDATASTORE_SECURITY_KEY_SALT;
extern NSString *const CDTDATASTORE_SECURITY_KEY_IV;
extern NSString *const CDTDATASTORE_SECURITY_KEY_ITERATIONS;
extern NSString *const CDTDATASTORE_SECURITY_KEY_VERSION;
extern NSString *const CDTDATASTORE_SECURITY_KEY_VERSION_NUMBER;
extern NSString *const CDTDATASTORE_SECURITY_KEY_DOCUMENT_ID;
