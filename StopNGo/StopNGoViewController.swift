//
//  File.swift
//  StopNGo
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/2/14.
//
//
/*
     File: StopNGoViewController.h
     File: StopNGoViewController.m
 Abstract: Document that captures stills to a QuickTime movie
  Version: 1.0

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

 Copyright (C) 2011 Apple Inc. All Rights Reserved.

 */

import UIKit
import AVFoundation
import AssetsLibrary

@objc(StopNGoViewController)
class StopNGoViewController: UIViewController {
    var started: Bool = false
    var frameDuration: CMTime = CMTimeMake(0, 0)
    var nextPTS: CMTime = CMTimeMake(0, 0)
    var assetWriter: AVAssetWriter?
    var assetWriterInput: AVAssetWriterInput?
    var stillImageOutput: AVCaptureStillImageOutput?
    var outputURL: URL?
    
    @IBOutlet var previewView: UIView!
    @IBOutlet var fpsSlider: UISlider!
    @IBOutlet var startFinishButton: UIBarButtonItem!
    @IBOutlet var takePictureButton: UIBarButtonItem!
    
    @discardableResult
    private func setupAVCapture() -> Bool {
        // 5 fps - taking 5 pictures will equal 1 second of video
        frameDuration = CMTimeMakeWithSeconds(1.0/5.0, 90000)
        
        let session = AVCaptureSession()
        session.sessionPreset = .high
        
        // Select a video device, make an input
        let backCamera = AVCaptureDevice.default(for: .video)
        let input: AVCaptureDeviceInput!
        do {
            input = try AVCaptureDeviceInput(device: backCamera!)
        } catch _ {
            return false
        }
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        // Make a still image output
        stillImageOutput = AVCaptureStillImageOutput()
        if session.canAddOutput(stillImageOutput!) {
            session.addOutput(stillImageOutput!)
        }
        
        // Make a preview layer so we can see the visual output of an AVCaptureSession
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspect
        previewLayer.frame = previewView.bounds
        
        // add the preview layer to the hierarchy
        let rootLayer = previewView.layer
        rootLayer.backgroundColor = UIColor.black.cgColor
        rootLayer.addSublayer(previewLayer)
        
        // start the capture session running, note this is an async operation
        // status is provided via notifications such as AVCaptureSessionDidStartRunningNotification/AVCaptureSessionDidStopRunningNotification
        session.startRunning()
        
        return true
    }
    
    private final func DegreesToRadians(_ degrees: CGFloat) -> CGFloat {
        return degrees * .pi / 180
    }
    
    private func setupAssetWriterForURL(_ fileURL: URL, formatDescription: CMFormatDescription) -> Bool {
        // allocate the writer object with our output file URL
        do {
            assetWriter = try AVAssetWriter(outputURL: fileURL, fileType: .mov)
        } catch _ {
            assetWriter = nil
            return false
        }
        
        // initialized a new input for video to receive sample buffers for writing
        // passing nil for outputSettings instructs the input to pass through appended samples, doing no processing before they are written
        assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
        assetWriterInput!.expectsMediaDataInRealTime = true
        if assetWriter!.canAdd(assetWriterInput!) {
            assetWriter!.add(assetWriterInput!)
        }
        
        // specify the prefered transform for the output file
        var rotationDegrees: CGFloat
        switch UIDevice.current.orientation {
        case .portraitUpsideDown:
            rotationDegrees = -90.0
        case .landscapeLeft: // no rotation
            rotationDegrees = 0.0
        case .landscapeRight:
            rotationDegrees = 180.0
        case .portrait:
            fallthrough
        case .unknown:
            fallthrough
        case .faceUp:
            fallthrough
        case .faceDown:
            fallthrough
        default:
            rotationDegrees = 90.0
        }
        let rotationRadians = DegreesToRadians(rotationDegrees)
        assetWriterInput!.transform = CGAffineTransform(rotationAngle: rotationRadians)
        
        // initiates a sample-writing at time 0
        nextPTS = kCMTimeZero
        assetWriter!.startWriting()
        assetWriter!.startSession(atSourceTime: nextPTS)
        
        return true
    }
    
    @IBAction func takePicture(_: AnyObject) {
        // initiate a still image capture, return immediately
        // the completionHandler is called when a sample buffer has been captured
        let stillImageConnection = stillImageOutput?.connection(with: .video)
        stillImageOutput?.captureStillImageAsynchronously(from: stillImageConnection!) {
            imageDataSampleBuffer, error in
            
            // set up the AVAssetWriter using the format description from the first sample buffer captured
            if self.assetWriter == nil {
                self.outputURL = URL(fileURLWithPath: "\(NSTemporaryDirectory())/\(mach_absolute_time()).mov")
                //NSLog("Writing movie to \"%@\"", outputURL)
                let formatDescription = CMSampleBufferGetFormatDescription(imageDataSampleBuffer!)
                if !self.setupAssetWriterForURL(self.outputURL!, formatDescription: formatDescription!) {
                    return
                }
            }
            
            // re-time the sample buffer - in this sample frameDuration is set to 5 fps
            var timingInfo = kCMTimingInfoInvalid
            timingInfo.duration = self.frameDuration
            timingInfo.presentationTimeStamp = self.nextPTS
            var sbufWithNewTiming: CMSampleBuffer? = nil
            let err = CMSampleBufferCreateCopyWithNewTiming(kCFAllocatorDefault,
                imageDataSampleBuffer!,
                1, // numSampleTimingEntries
                &timingInfo,
                &sbufWithNewTiming)
            if err != 0 {
                return
            }
            
            // append the sample buffer if we can and increment presnetation time
            if self.assetWriterInput?.isReadyForMoreMediaData ?? false {
                if self.assetWriterInput!.append(sbufWithNewTiming!) {
                    self.nextPTS = CMTimeAdd(self.frameDuration, self.nextPTS)
                } else {
                    let error = self.assetWriter!.error
                    NSLog("failed to append sbuf: \(error!)")
                }
            }
            
            // release the copy of the sample buffer we made
        }
    }
    
    private func saveMovieToCameraRoll() {
        // save the movie to the camera roll
        let library = ALAssetsLibrary()
        //NSLog("writing \"%@\" to photos album", outputURL!)
        library.writeVideoAtPath(toSavedPhotosAlbum: outputURL) {
            assetURL, error in
            if error != nil {
                NSLog("assets library failed (\(error!))")
            } else {
                do {
                    try FileManager.default.removeItem(at: self.outputURL!)
                } catch _ {
                    NSLog("Couldn't remove temporary movie file \"\(self.outputURL!)\"")
                }
            }
            self.outputURL = nil
        }
    }
    
    @IBAction func startStop(_ sender: UIBarButtonItem) {
        if started {
            if assetWriter != nil {
                assetWriterInput!.markAsFinished()
                assetWriter!.finishWriting {
                    self.assetWriterInput = nil
                    self.saveMovieToCameraRoll()
                    self.assetWriter = nil
                }
            }
            sender.title = "Start"
            takePictureButton.isEnabled = false
        } else {
            sender.title = "Finish"
            takePictureButton.isEnabled = true
            
        }
        started = !started
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
    //MARK: - View lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupAVCapture()
        // Do any additional setup after loading the view, typically from a nib.
    }
    
    override var shouldAutorotate : Bool {
        return false
    }
    
    
}
