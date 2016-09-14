//
//  ViewController.swift
//  Word Sense
//
//  Created by Adam Gravely on 9/9/16.
//  Copyright © 2016 Spacebar. All rights reserved.
//

import UIKit

fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?):
        return l < r
    case (nil, _?):
        return true
    default:
        return false
    }
}

fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?):
        return l > r
    default:
        return rhs < lhs
    }
}

class ViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate, NVActivityIndicatorViewable {
    
    @IBOutlet weak var imageView: UIImageView!
    let imagePicker = UIImagePickerController()
    @IBOutlet var spinner: UIActivityIndicatorView!
    @IBOutlet weak var textResults: UITextView!
    @IBOutlet weak var wordCount: UILabel!
    @IBOutlet weak var textFoundLabel: UILabel!
    
    var API_KEY = "AIzaSyBo42-xNuufRV_6D39SjL1kTDaJokn2Znk"
    var liveCount: Int = 0
    
    @IBAction func loadImageButtonTapped(_ sender: UIButton) {
        imagePicker.allowsEditing = false
        imagePicker.sourceType = .photoLibrary
        
        present(imagePicker, animated: true, completion: nil)
    }
    
    @IBAction func openCamera(_ sender: AnyObject) {
        imageView.isHidden = false
        if UIImagePickerController.isSourceTypeAvailable(UIImagePickerControllerSourceType.camera) {
            let imagePicker = UIImagePickerController()
            imagePicker.delegate = self
            imagePicker.sourceType = .camera
            imagePicker.allowsEditing = false
            self.present(imagePicker, animated: true, completion: nil)
        }
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        if let pickedImage = info[UIImagePickerControllerOriginalImage] as? UIImage {
            imageView.contentMode = .scaleAspectFit
            imageView.isHidden = true // You could optionally display the image here by setting imageView.image = pickedImage
            spinner.startAnimating()
            startActivityAnimating(CGSize(width: 100, height: 100), message: "Analyzing...", type: NVActivityIndicatorType(rawValue: 16))
            textResults.isHidden = true
            wordCount.isHidden = true
            textFoundLabel.isHidden = true
            
            if(!Reachability.isConnectedToNetwork()) {
                spinner.stopAnimating()
                stopActivityAnimating()
                self.textResults.isHidden = false
                self.wordCount.isHidden = false
                self.textFoundLabel.isHidden = false
                self.wordCount.text = "No Connection"
                self.textFoundLabel.text = "..."
                self.textResults.text = "Image Sensing Requires Internet Connection...\n\nTry connecting to a WiFi signal"
            }
            else {
                // Base64 encode the image and create the request
                let binaryImageData = base64EncodeImage(pickedImage)
                createRequest(binaryImageData)
            }
        }
        
        dismiss(animated: true, completion: nil)
        imageView.isHidden = true
    }
    
    func resizeImage(_ imageSize: CGSize, image: UIImage) -> Data {
        UIGraphicsBeginImageContext(imageSize)
        image.draw(in: CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        let resizedImage = UIImagePNGRepresentation(newImage!)
        UIGraphicsEndImageContext()
        return resizedImage!
    }
    
    func base64EncodeImage(_ image: UIImage) -> String {
        var imagedata = UIImagePNGRepresentation(image)
        
        // Resize the image if it exceeds the 2MB API limit
        if ((imagedata?.count)! > 2097152) {
            let oldSize: CGSize = image.size
            let newSize: CGSize = CGSize(width: 800, height: oldSize.height / oldSize.width * 800)
            imagedata = resizeImage(newSize, image: image)
        }
        
        return imagedata!.base64EncodedString(options: .endLineWithCarriageReturn)
    }
    
    func createRequest(_ imageData: String) {
        // Create our request URL
        let request = NSMutableURLRequest(
            url: URL(string: "https://vision.googleapis.com/v1/images:annotate?key=\(API_KEY)")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(
            Bundle.main.bundleIdentifier ?? "",
            forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        
        // Build our API request
        let jsonRequest: [String: Any] = [
            "requests": [
                "image": [
                    "content": imageData
                ],
                "features": [
                    [
                        "type": "TEXT_DETECTION"
                        
                    ]
                ]
            ]
        ]
        
        // Serialize the JSON
        request.httpBody = try! JSONSerialization.data(withJSONObject: jsonRequest, options: [])
        
        // Run the request on a background thread
        DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.default).async(execute: {
            self.runRequestOnBackgroundThread(request as URLRequest)
        });
        
    }
    
    func runRequestOnBackgroundThread(_ request: URLRequest) {
        
        let session = URLSession.shared
        
        // run the request
        let task = session.dataTask(with: request as URLRequest, completionHandler: {
            data, response, error in
            self.analyzeResults(data!)
        })
        task.resume()
    }
    
    func analyzeResults(_ dataToParse: Data) {
        
        // Update UI on the main thread
        DispatchQueue.main.async(execute: {
            
            
            // Use SwiftyJSON to parse results
            let json = JSON(data: dataToParse)
            let errorObj: JSON = json["error"]
            
            self.spinner.stopAnimating()
            self.stopActivityAnimating()
            self.imageView.isHidden = true
            //
            self.textResults.isHidden = false
            self.wordCount.isHidden = false
            self.textFoundLabel.isHidden = false
            //
            
            // Check for errors
            if (errorObj.dictionaryValue != [:]) {
                self.wordCount.isHidden = true
                self.textResults.text = "Error code \(errorObj["code"]): \(errorObj["message"])"
            }
            else {
                // Parse the response
                print(json)
                let responses: JSON = json["responses"][0]
                
                //Get text annotations
                let textAnnotations: JSON = responses["textAnnotations"]
                let numWords: Int = textAnnotations.count
                self.liveCount = (numWords - 1)
                var words: Array<String> = []
                
                if numWords > 0 {
                    var textResultsText:String = ""
                    for index in 1..<numWords {
                        let word = textAnnotations[index]["description"].stringValue
                        words.append(word)
                    }
                    for word in words {
                        //if it's not the last item add a comma
                        if words[words.count - 1] != word {
                            textResultsText += "\(word) "
                        } else {
                            textResultsText += "\(word)"
                        }
                    }
                    self.textResults.text = textResultsText
                    self.wordCount.text = "\(self.liveCount) Words"
                } else {
                    self.textResults.text = "No text found"
                    self.wordCount.text = "x  -  x"
                    
                }
            }
        })
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        dismiss(animated: true, completion: nil)
    }
    
    override func viewDidLoad(){
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        imagePicker.delegate = self
        textResults.isHidden = true
        wordCount.isHidden = true
        textFoundLabel.isHidden = true
        spinner.hidesWhenStopped = true
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}


