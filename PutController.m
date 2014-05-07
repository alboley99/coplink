/*
     File: PutController.m
 Abstract: Manages the Put tab.
  Version: 1.4
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright (C) 2013 Apple Inc. All Rights Reserved.
 
 */

#import "PutController.h"

#import "NetworkManager.h"

#import <AssetsLibrary/ALAsset.h>
#import <AssetsLibrary/ALAssetsFilter.h>
#import <AssetsLibrary/ALAssetsGroup.h>
#import <AssetsLibrary/ALAssetRepresentation.h>
#import <CoreLocation/CoreLocation.h>

#include <CFNetwork/CFNetwork.h>

enum {
    kSendBufferSize = 32768
};

@interface PutController () <UITextFieldDelegate, NSStreamDelegate, UIPickerViewDelegate, UIPickerViewDataSource>

// things for IB

// @property (nonatomic, strong, readwrite) IBOutlet UITextField *               urlText;
// @property (nonatomic, strong, readwrite) IBOutlet UITextField *               usernameText;
// @property (nonatomic, strong, readwrite) IBOutlet UITextField *               passwordText;
@property (nonatomic, strong, readwrite) IBOutlet UILabel *                   statusLabel;
@property (nonatomic, strong, readwrite) IBOutlet UIActivityIndicatorView *   activityIndicator;
@property (nonatomic, strong, readwrite) IBOutlet UIButton *           cancelButton;
@property (nonatomic, strong, readwrite) IBOutlet
UIImageView *           imageView;
@property (nonatomic, strong, readwrite) IBOutlet
UITextView *           incidentText;

- (IBAction)sendAction:(UIView *)sender;
- (IBAction)cancelAction:(id)sender;

// Properties that don't need to be seen by the outside world.

@property (nonatomic, assign, readonly ) BOOL              isSending;
@property (nonatomic, strong, readwrite) NSOutputStream *  networkStream;
@property (nonatomic, strong, readwrite) NSInputStream *   fileStream;
@property (nonatomic, assign, readonly ) uint8_t *         buffer;
@property (nonatomic, assign, readwrite) size_t            bufferOffset;
@property (nonatomic, assign, readwrite) size_t            bufferLimit;

@property (nonatomic, assign, readwrite ) BOOL              mainFileSent;
@property (nonatomic, assign, readwrite ) NSString*         fileName;

@property (nonatomic, strong, readwrite ) NSString*         officerLocation;

@end

@implementation PutController
{
    uint8_t                     _buffer[kSendBufferSize];
}

#pragma mark * Status management

// These methods are used by the core transfer code to update the UI.

- (void)sendDidStart
{
    self.statusLabel.text = @"Sending";
    self.cancelButton.enabled = YES;
    [self.activityIndicator startAnimating];
    [[NetworkManager sharedInstance] didStartNetworkOperation];
}

- (void)updateStatus:(NSString *)statusString
{
    assert(statusString != nil);
    self.statusLabel.text = statusString;
}

- (void)sendDidStopWithStatus:(NSString *)statusString
{
    if (statusString == nil) {
        statusString = @"Upload succeeded";
        
        
    }
    self.statusLabel.text = statusString;
    self.cancelButton.enabled = NO;
    [self.activityIndicator stopAnimating];
    [[NetworkManager sharedInstance] didStopNetworkOperation];
    
    
    // Now send the meta data file
    
    if ([statusString  isEqual: @"Upload succeeded"]) {
    
    if (!self.mainFileSent)
    {
        
        // We have just sent the main file
        self.mainFileSent = true;
        
        // Now send the metedatafile
        
        // Get the base meta data file
        
        NSString *  filePath;
        filePath = [[NSBundle mainBundle] pathForResource:[NSString stringWithFormat:@"newvideo"] ofType:@"mrss"];
        
        NSError * error;
        NSString * stringFromFile;

        stringFromFile = [[NSString alloc] initWithContentsOfFile:filePath encoding:NSWindowsCP1250StringEncoding error:&error];
        
        
        // Add the incident text into the meta data file
        
      
        NSString *copyString = [stringFromFile stringByReplacingOccurrencesOfString:@"This is an incident"
                                                           withString:self.incidentText.text];
        
        NSString *newStringFromFile;
        
        if (_officerLocation != Nil)
        {
        
        // Add the location id location services is turned on
        newStringFromFile = [copyString stringByReplacingOccurrencesOfString:@"No location provided"
                                                                                withString:_officerLocation];
        }
        else
        {
        newStringFromFile = copyString;
        }
        
                
        // Get the path of where to save the updated mrss file to
        
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        filePath = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"newvideo.mrss"];
        

        [newStringFromFile writeToFile:filePath atomically:YES encoding:NSWindowsCP1250StringEncoding error:Nil];
        
        // Now upload the meta data file
        
        
        assert(filePath != nil);
        [self startSend:filePath];
        self.mainFileSent = true;
        
    }
    }
    
    
}

#pragma mark * Core transfer code

// This is the code that actually does the networking.

// Because buffer is declared as an array, you have to use a custom getter.  
// A synthesised getter doesn't compile.

- (uint8_t *)buffer
{
    return self->_buffer;
}

- (BOOL)isSending
{
    return (self.networkStream != nil);
}

- (void)startSend:(NSString *)filePath
{
    BOOL                    success;
    NSURL *                 url;
    
    assert(filePath != nil);
    assert([[NSFileManager defaultManager] fileExistsAtPath:filePath]);
    assert( [filePath.pathExtension isEqual:@"png"] || [filePath.pathExtension isEqual:@"jpg"] || [filePath.pathExtension isEqual:@"mrss"] || [filePath.pathExtension isEqual:@"mp4"] || [filePath.pathExtension isEqual:@"m4v"] || [filePath.pathExtension isEqual:@"mov"]);
    
    assert(self.networkStream == nil);      // don't tap send twice in a row!
    assert(self.fileStream == nil);         // ditto

    // First get and check the URL.
    
  //AJH  url = [[NetworkManager sharedInstance] smartURLForString:self.urlText.text];
    url = [[NetworkManager sharedInstance] smartURLForString:@"ftp.6xw.co/videoingest"];
    success = (url != nil);
    
    if (success) {
        // Add the last part of the file name to the end of the URL to form the final 
        // URL that we're going to put to.
        
        url = CFBridgingRelease(
            CFURLCreateCopyAppendingPathComponent(NULL, (__bridge CFURLRef) url, (__bridge CFStringRef) [filePath lastPathComponent], false)
        );
        success = (url != nil);
    }
    
    // If the URL is bogus, let the user know.  Otherwise kick off the connection.

    if ( ! success) {
        self.statusLabel.text = @"Invalid URL";
    } else {

        // Open a stream for the file we're going to send.  We do not open this stream; 
        // NSURLConnection will do it for us.
        
        self.fileStream = [NSInputStream inputStreamWithFileAtPath:filePath];
        assert(self.fileStream != nil);
        
        [self.fileStream open];
        
        // Open a CFFTPStream for the URL.

        self.networkStream = CFBridgingRelease(
            CFWriteStreamCreateWithFTPURL(NULL, (__bridge CFURLRef) url)
        );
        assert(self.networkStream != nil);

//AJH        if ([self.usernameText.text length] != 0) {
//AJH            success = [self.networkStream setProperty:self.usernameText.text forKey:(id)kCFStreamPropertyFTPUserName];
//AJH            assert(success);
//AJH            success = [self.networkStream setProperty:self.passwordText.text forKey:(id)kCFStreamPropertyFTPPassword];
//AJH            assert(success);
//AJH        }
        
        
        success = [self.networkStream setProperty:@"6xw.co" forKey:(id)kCFStreamPropertyFTPUserName];
        assert(success);
        success = [self.networkStream setProperty:@"Conservatory1" forKey:(id)kCFStreamPropertyFTPPassword];
        assert(success);

        self.networkStream.delegate = self;
        [self.networkStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [self.networkStream open];

        // Tell the UI we're sending.
        
        [self sendDidStart];
    }
}

- (void)stopSendWithStatus:(NSString *)statusString
{
    if (self.networkStream != nil) {
        [self.networkStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        self.networkStream.delegate = nil;
        [self.networkStream close];
        self.networkStream = nil;
    }
    if (self.fileStream != nil) {
        [self.fileStream close];
        self.fileStream = nil;
    }
    [self sendDidStopWithStatus:statusString];
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
    // An NSStream delegate callback that's called when events happen on our 
    // network stream.
{
    #pragma unused(aStream)
    assert(aStream == self.networkStream);

    switch (eventCode) {
        case NSStreamEventOpenCompleted: {
            [self updateStatus:@"Opened connection"];
        } break;
        case NSStreamEventHasBytesAvailable: {
            assert(NO);     // should never happen for the output stream
        } break;
        case NSStreamEventHasSpaceAvailable: {
            [self updateStatus:@"Sending"];
            
            // If we don't have any data buffered, go read the next chunk of data.
            
            if (self.bufferOffset == self.bufferLimit) {
                NSInteger   bytesRead;
                
                bytesRead = [self.fileStream read:self.buffer maxLength:kSendBufferSize];
                
                if (bytesRead == -1) {
                    [self stopSendWithStatus:@"File read error"];
                } else if (bytesRead == 0) {
                    [self stopSendWithStatus:nil];
                } else {
                    self.bufferOffset = 0;
                    self.bufferLimit  = bytesRead;
                }
            }
            
            // If we're not out of data completely, send the next chunk.
            
            if (self.bufferOffset != self.bufferLimit) {
                NSInteger   bytesWritten;
                bytesWritten = [self.networkStream write:&self.buffer[self.bufferOffset] maxLength:self.bufferLimit - self.bufferOffset];
                assert(bytesWritten != 0);
                if (bytesWritten == -1) {
                    [self stopSendWithStatus:@"Network write error"];
                } else {
                    self.bufferOffset += bytesWritten;
                }
            }
        } break;
        case NSStreamEventErrorOccurred: {
            [self stopSendWithStatus:@"Stream open error"];
        } break;
        case NSStreamEventEndEncountered: {
            // ignore
        } break;
        default: {
            assert(NO);
        } break;
    }
}

#pragma mark * Actions

- (IBAction)sendAction:(UIView *)sender
{
    assert( [sender isKindOfClass:[UIView class]] );

    if ( ! self.isSending ) {
  
    
      
        assert(sender.tag >= 0);
        
        self.mainFileSent = false;
        
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *filePath = [[paths objectAtIndex:0] stringByAppendingPathComponent:self.fileName];
        
        
 //       filePath = [[NSBundle mainBundle] pathForResource:[NSString stringWithFormat:@"testfile"] ofType:@"png"];
    	   assert(filePath != nil);
        [self startSend:filePath];
        
//        filePath = [[NSBundle mainBundle] pathForResource:[NSString stringWithFormat:@"newvideo"] ofType:@"mrss"];
        
//       filePath = [[NetworkManager sharedInstance] pathForTestImage:(NSUInteger) sender.tag];
 
 //       assert(filePath != nil);
  
//        [self startSend:filePath];
    }
}

- (IBAction)cancelAction:(id)sender
{
    #pragma unused(sender)
    [self stopSendWithStatus:@"Cancelled"];
}


- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [_incidentText resignFirstResponder];
}

- (void)textFieldDidEndEditing:(UITextField *)textField
    // A delegate method called by the URL text field when the editing is complete. 
    // We save the current value of the field in our settings.
{
    NSString *  defaultsKey;
    NSString *  newValue;
    NSString *  oldValue;
    
//    if (textField == self.urlText) {
//        defaultsKey = @"PutURLText";
//    } else if (textField == self.usernameText) {
//        defaultsKey = @"Username";
//    } else if (textField == self.passwordText) {
//        defaultsKey = @"Password";
//    } else {
//        assert(NO);
//        defaultsKey = nil;          // quieten warning
//    }

    newValue = textField.text;
    oldValue = [[NSUserDefaults standardUserDefaults] stringForKey:defaultsKey];

    // Save the URL text if it's changed.
    
    assert(newValue != nil);        // what is UITextField thinking!?!
    assert(oldValue != nil);        // because we registered a default
    
    if ( ! [newValue isEqual:oldValue] ) {
        [[NSUserDefaults standardUserDefaults] setObject:newValue forKey:defaultsKey];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
    // A delegate method called by the URL text field when the user taps the Return 
    // key.  We just dismiss the keyboard.
{
    #pragma unused(textField)
//    assert( (textField == self.urlText) || (textField == self.usernameText) || (textField == self.passwordText) );
    [textField resignFirstResponder];
    return NO;
}



#pragma mark * View controller boilerplate

- (void)viewDidLoad
{
    [super viewDidLoad];
//    assert(self.urlText != nil);
//    assert(self.usernameText != nil);
//    assert(self.passwordText != nil);
    assert(self.statusLabel != nil);
    assert(self.activityIndicator != nil);
    assert(self.cancelButton != nil);
    
    // Start Location Services to send a location message
    
    // Create the location manager if this object does not
    // already have one.
    
    if (nil == locationManager)
    locationManager = [[CLLocationManager alloc] init];
    
    locationManager.delegate = self;
    locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    //   locationManager.desiredAccuracy = kCLLocationAccuracyKilometer;
    
    // Set a movement threshold for new events.
    locationManager.distanceFilter = 500; // meters
    
    [locationManager startUpdatingLocation];
    NSLog(@"Started Location Updates");


//    self.urlText.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"PutURLText"];
//AJH        self.urlText.text = @"ftp.6xw.co/videoingest";
    // The setup of usernameText and passwordText deferred to -viewWillAppear: 
    // because those values are shared by multiple tabs.
    
    self.activityIndicator.hidden = YES;
    self.statusLabel.text = @"";
    self.cancelButton.enabled = NO;
    
    
    _countryNames = @[@"Australia (AUD)", @"China (CNY)",
                      @"France (EUR)", @"Great Britain (GBP)", @"Japan (JPY)"];
    
    _exchangeRates = @[ @0.9922f, @6.5938f, @0.7270f,
                        @0.6206f, @81.57f];
    
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    
    // Enumerate just the photos and videos group by using ALAssetsGroupSavedPhotos.
    [library enumerateGroupsWithTypes:ALAssetsGroupSavedPhotos usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
        
        // Within the group enumeration block, filter to enumerate just photos.
        [group setAssetsFilter:[ALAssetsFilter allAssets]];
        
        // Chooses the photo at the last index
        [group enumerateAssetsAtIndexes:[NSIndexSet indexSetWithIndex:([group numberOfAssets]-1)]
                                options:0
                             usingBlock:^(ALAsset *alAsset, NSUInteger index, BOOL *innerStop) {
                                 
                                 // The end of the enumeration is signaled by asset == nil.
                                 if (alAsset) {
                                     
                                    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
                                    NSString *filePath;
                                     
                                     if ([[alAsset valueForProperty:ALAssetPropertyType] isEqualToString:ALAssetTypeVideo])
                                     {
                                         self.fileName = @"media.mov";
                                     }
                                         else
                                    {
                                        self.fileName = @"media.png";
                                    }
                                         
                                     
                                     filePath = [[paths objectAtIndex:0] stringByAppendingPathComponent:self.fileName];
                                     
                                     // Create a file handle to write the file at your destination path
                                     [[NSFileManager defaultManager] createFileAtPath:filePath contents:nil attributes:nil];
                                     NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:filePath];
                                     if (!handle)
                                     {
                                         // Handle error here…
                                     }
                                     
                                     // Create a buffer for the asset
                                     
                                    
                                     static const NSUInteger BufferSize = 1024*1024;
                                     ALAssetRepresentation *rep = [alAsset defaultRepresentation];
                                     uint8_t *buffer = calloc(BufferSize, sizeof(*buffer));
                                     NSUInteger offset = 0, bytesRead = 0;
                                     
                                     // Read the buffer and write the data to your destination path as you go
                                     do
                                     {
                                         @try
                                         {
                                             bytesRead = [rep getBytes:buffer fromOffset:offset length:BufferSize error:NULL];
                                             [handle writeData:[NSData dataWithBytesNoCopy:buffer length:bytesRead freeWhenDone:NO]];
                                             offset += bytesRead;
                                         }
                                         @catch (NSException *exception)
                                         {
                                             free(buffer);
                                             
                                             // Handle the exception here...
                                         }
                                     } while (bytesRead > 0);
                                     
                                     // 
                                     free(buffer);
                                     
                                    
                                     UIImage *latestPhoto = [UIImage imageWithCGImage:[rep fullResolutionImage]];
                                    [self.imageView setImage:latestPhoto];
                                     
                                     
                                     
                                     
 //
 //                                    ALAssetRepresentation *representation = [alAsset defaultRepresentation];
  //                                   UIImage *latestPhoto = [UIImage imageWithCGImage:[representation fullResolutionImage]];
                                     
                                     // Do something interesting with the AV asset.
 //                                    [self.imageView setImage:latestPhoto];
                                     
                                     
                                     // Create path
 //                                    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
 //                                    NSString *filePath = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"testimage.png"];
                                   
                                     
  //                                   // Save image.
  //                                   [UIImagePNGRepresentation(latestPhoto) writeToFile:filePath atomically:YES];
                                     
                                     
                                     
                                 }
                             }];
    }
                         failureBlock: ^(NSError *error) {
                             // Typically you should handle an error more gracefully than this.
                             NSLog(@"No groups");
                         }];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
//    self.usernameText.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"Username"];
//    self.passwordText.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"Password"];
    
//    self.usernameText.text = @"6xw.co";
//    self.passwordText.text = @"Conservatory1";
    
}

- (void)viewDidUnload
{
    [super viewDidUnload];

//AJH    self.urlText = nil;
//    self.usernameText = nil;
//    self.passwordText = nil;
    self.statusLabel = nil;
    self.activityIndicator = nil;
    self.cancelButton = nil;
}

- (void)dealloc
{
    [self stopSendWithStatus:@"Stopped"];
}

- (void)locationManager:(CLLocationManager *)manager
     didUpdateLocations:(NSArray *)locations

{
    // If it's a relatively recent event, turn off updates to save power.
    CLLocation* location = [locations lastObject];
    NSDate* eventDate = location.timestamp;
    NSTimeInterval howRecent = [eventDate timeIntervalSinceNow];
    
    
    if (abs(howRecent) < 15.0) {
        // If the event is recent, do something with it.
        NSLog(@"latitude %+.6f\ns, longitude %+.6f\ns, accuracy %g\n",
              location.coordinate.latitude,
              location.coordinate.longitude,location.horizontalAccuracy);
        
        _officerLocation = [NSString stringWithFormat:@"%+.6f,%+.6f",location.coordinate.latitude, location.coordinate.longitude];
        
        float latitude = location.coordinate.latitude;
        float longitude = location.coordinate.latitude;
        
        // Location has been found so disable location services
        
        [locationManager stopUpdatingLocation];
        
        
    }
}


@end
