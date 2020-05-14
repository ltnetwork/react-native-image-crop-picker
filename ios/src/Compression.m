//
//  Compression.m
//  imageCropPicker
//
//  Created by Ivan Pusic on 12/24/16.
//  Copyright © 2016 Ivan Pusic. All rights reserved.
//

#import "Compression.h"

@implementation Compression

- (instancetype)init {
    NSMutableDictionary *dic = [[NSMutableDictionary alloc] initWithDictionary:@{
                                                                                 @"640x480": AVAssetExportPreset640x480,
                                                                                 @"960x540": AVAssetExportPreset960x540,
                                                                                 @"1280x720": AVAssetExportPreset1280x720,
                                                                                 @"1920x1080": AVAssetExportPreset1920x1080,
                                                                                 @"LowQuality": AVAssetExportPresetLowQuality,
                                                                                 @"MediumQuality": AVAssetExportPresetMediumQuality,
                                                                                 @"HighestQuality": AVAssetExportPresetHighestQuality,
                                                                                 @"Passthrough": AVAssetExportPresetPassthrough,
                                                                                 }];
    
    if (@available(iOS 9.0, *)) {
        [dic addEntriesFromDictionary:@{@"3840x2160": AVAssetExportPreset3840x2160}];
    } else {
        // Fallback on earlier versions
    }
    
    self.exportPresets = dic;
    
    return self;
}

- (ImageResult*) compressImageDimensions:(UIImage*)image
                   compressImageMaxWidth:(CGFloat)maxWidth
                  compressImageMaxHeight:(CGFloat)maxHeight
                              intoResult:(ImageResult*)result {
    
    CGFloat oldWidth = image.size.width;
    CGFloat oldHeight = image.size.height;
    
    int newWidth = 0;
    int newHeight = 0;
    
    if (maxWidth < maxHeight) {
        newWidth = maxWidth;
        newHeight = (oldHeight / oldWidth) * newWidth;
    } else {
        newHeight = maxHeight;
        newWidth = (oldWidth / oldHeight) * newHeight;
    }
    CGSize newSize = CGSizeMake(newWidth, newHeight);
    
    UIGraphicsBeginImageContext(newSize);
    [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    UIImage *resizedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    result.width = [NSNumber numberWithFloat:newWidth];
    result.height = [NSNumber numberWithFloat:newHeight];
    result.image = resizedImage;
    return result;
}

- (ImageResult*) compressImage:(UIImage*)image
                   withOptions:(NSDictionary*)options {
    
    ImageResult *result = [[ImageResult alloc] init];
    result.width = @(image.size.width);
    result.height = @(image.size.height);
    result.image = image;
    result.mime = @"image/jpeg";
    
    NSNumber *compressImageMaxWidth = [options valueForKey:@"compressImageMaxWidth"];
    NSNumber *compressImageMaxHeight = [options valueForKey:@"compressImageMaxHeight"];
    
    // determine if it is necessary to resize image
    BOOL shouldResizeWidth = (compressImageMaxWidth != nil && [compressImageMaxWidth floatValue] < image.size.width);
    BOOL shouldResizeHeight = (compressImageMaxHeight != nil && [compressImageMaxHeight floatValue] < image.size.height);
    
    if (shouldResizeWidth || shouldResizeHeight) {
        CGFloat maxWidth = compressImageMaxWidth != nil ? [compressImageMaxWidth floatValue] : image.size.width;
        CGFloat maxHeight = compressImageMaxHeight != nil ? [compressImageMaxHeight floatValue] : image.size.height;
        
        [self compressImageDimensions:image
                compressImageMaxWidth:maxWidth
               compressImageMaxHeight:maxHeight
                           intoResult:result];
    }
    
    // parse desired image quality
    NSNumber *compressQuality = [options valueForKey:@"compressImageQuality"];
    if (compressQuality == nil) {
        compressQuality = [NSNumber numberWithFloat:0.8];
    }
    
    // convert image to jpeg representation
    result.data = UIImageJPEGRepresentation(result.image, [compressQuality floatValue]);
    
    return result;
}

- (void)compressVideo:(NSURL*)inputURL
            outputURL:(NSURL*)outputURL
          withOptions:(NSDictionary*)options
              handler:(void (^)(AVAssetExportSession*))handler {
    
    NSString *presetKey = [options valueForKey:@"compressVideoPreset"];
    if (presetKey == nil) {
        presetKey = @"MediumQuality";
    }
    
    NSString *preset = [self.exportPresets valueForKey:presetKey];
    if (preset == nil) {
        preset = AVAssetExportPresetMediumQuality;
    }
    
    [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:inputURL options:nil];
    
    NSString *fileExtension = [inputURL pathExtension];
    
    if ([fileExtension isEqualToString:@"MOV"]) {
        //inspired from https://stackoverflow.com/questions/20402106/how-to-correct-orientation-of-video-in-objective-c/28056569
        NSError *error = nil;
        
        AVMutableComposition *composition = [AVMutableComposition composition];
        AVMutableCompositionTrack *compositionVideoTrack = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
        AVMutableCompositionTrack *compositionAudioTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
        
        AVAssetTrack *videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
        AVAssetTrack *audioTrack = [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];
        [compositionVideoTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, asset.duration) ofTrack:videoTrack atTime:kCMTimeZero error:&error];
        [compositionAudioTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, asset.duration) ofTrack:audioTrack atTime:kCMTimeZero error:&error];
        
        CGAffineTransform transformToApply = videoTrack.preferredTransform;
        AVMutableVideoCompositionLayerInstruction *layerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:compositionVideoTrack];
        [layerInstruction setTransform:transformToApply atTime:kCMTimeZero];
        [layerInstruction setOpacity:0.0 atTime:asset.duration];
        
        AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
        instruction.timeRange = CMTimeRangeMake( kCMTimeZero, asset.duration);
        instruction.layerInstructions = @[layerInstruction];
        
        float fps = videoTrack.nominalFrameRate;
        AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoComposition];
        videoComposition.instructions = @[instruction];
        videoComposition.frameDuration = CMTimeMake(1, fps); //select the frames per second
        videoComposition.renderScale = 1.0;
        
        CGSize naturalSize = [[[asset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0] naturalSize];
        CGSize size = CGSizeApplyAffineTransform(naturalSize, videoTrack.preferredTransform);
        CGFloat width = fabs(size.width);
        CGFloat height = fabs(size.height);
        videoComposition.renderSize = CGSizeMake(width, height);
        
        AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:composition presetName:preset];
        
        exportSession.outputURL = outputURL;
        exportSession.outputFileType = AVFileTypeMPEG4;
        exportSession.videoComposition = videoComposition;
        exportSession.shouldOptimizeForNetworkUse = NO;
        exportSession.timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration);
        
        [exportSession exportAsynchronouslyWithCompletionHandler:^(void) {
            handler(exportSession);
        }];
    } else {
        AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:asset presetName:preset];
        
        exportSession.outputURL = outputURL;
        exportSession.outputFileType = AVFileTypeMPEG4;
        exportSession.shouldOptimizeForNetworkUse = NO;
        exportSession.timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration);
        
        [exportSession exportAsynchronouslyWithCompletionHandler:^(void) {
            handler(exportSession);
        }];

    }
}

@end
