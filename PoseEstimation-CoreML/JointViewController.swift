//
//  ViewController.swift
//  PoseEstimation-CoreML
//
//  Created by GwakDoyoung on 05/07/2018.
//  Copyright © 2018 tucan9389. All rights reserved.
//

import UIKit
import Vision
import CoreMedia

struct BodyPoint {
    let maxPoint: CGPoint
    let maxConfidence: Double
}

class JointViewController: UIViewController {
    public typealias DetectObjectsCompletion = ([BodyPoint?]?, Error?) -> Void
    
    // MARK: - UI Properties
    @IBOutlet weak var videoPreview: UIView!
    @IBOutlet weak var poseView: PoseView!
    @IBOutlet weak var labelsTableView: UITableView!
    
    @IBOutlet weak var inferenceLabel: UILabel!
    @IBOutlet weak var etimeLabel: UILabel!
    @IBOutlet weak var fpsLabel: UILabel!
    
    // MARK - Inference Result Data
    private var tableData: [BodyPoint?] = []
    
    // MARK - Performance Measurement Property
    private let 👨‍🔧 = 📏()
    
    // MARK - Core ML model
    typealias EstimationModel = model_cpm
    
    // MARK: - Vision Properties
    var request: VNCoreMLRequest!
    var visionModel: VNCoreMLModel! {
        didSet {
            request = VNCoreMLRequest(model: visionModel, completionHandler: visionRequestDidComplete)
            request.imageCropAndScaleOption = .scaleFill
        }
    }
    
    // MARK: - AV Property
    var videoCapture: VideoCapture!
    
    // MARK: - View Controller Life Cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // MobileNet 클래스는 `MobileNet.mlmodel`를 프로젝트에 넣고, 빌드시키면 자동으로 생성된 랩퍼 클래스
        // MobileNet에서 만든 model: MLModel 객체로 (Vision에서 사용할) VNCoreMLModel 객체를 생성
        // Vision은 모델의 입력 크기(이미지 크기)에 따라 자동으로 조정해 줌
        visionModel = try? VNCoreMLModel(for: EstimationModel().model)
        
        // setup camera
        setUpCamera()
        
        // setup tableview datasource on bottom
        labelsTableView.dataSource = self
        
        // setup label point ui on pose view
        poseView.setUpOutputComponent()
        
        // 성능측정용 델리게이트 설정
        👨‍🔧.delegate = self
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    // MARK: - SetUp Video
    func setUpCamera() {
        videoCapture = VideoCapture()
        videoCapture.delegate = self
        videoCapture.fps = 30
        videoCapture.setUp(sessionPreset: .vga640x480) { success in
            
            if success {
                // UI에 비디오 미리보기 뷰 넣기
                if let previewLayer = self.videoCapture.previewLayer {
                    self.videoPreview.layer.addSublayer(previewLayer)
                    self.resizePreviewLayer()
                }
                
                // 초기설정이 끝나면 라이브 비디오를 시작할 수 있음
                self.videoCapture.start()
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        resizePreviewLayer()
    }
    
    func resizePreviewLayer() {
        videoCapture.previewLayer?.frame = videoPreview.bounds
    }
}

extension JointViewController {
    // MARK: - Inferencing
    func predictUsingVision(pixelBuffer: CVPixelBuffer) {
        // Vision이 입력이미지를 자동으로 크기조정을 해줄 것임.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        try? handler.perform([request])
    }
    
    // MARK: - Poseprocessing
    func visionRequestDidComplete(request: VNRequest, error: Error?) {
        self.👨‍🔧.🏷(with: "endInference")
        if let observations = request.results as? [VNCoreMLFeatureValueObservation],
            let heatmap = observations.first?.featureValue.multiArrayValue {
            
            // convert heatmap to [keypoint]
            let n_kpoints = convert(heatmap: heatmap)
            
            DispatchQueue.main.sync {
                // draw line
                self.poseView.bodyPoints = n_kpoints
                
                // show key points description
                self.showKeypointsDescription(with: n_kpoints)
                
                // end of measure
                self.👨‍🔧.🎬🤚()
            }
        }
    }
    
    func convert(heatmap: MLMultiArray) -> [BodyPoint?] {
        guard heatmap.shape.count >= 3 else {
            print("heatmap's shape is invalid. \(heatmap.shape)")
            return []
        }
        let keypoint_number = heatmap.shape[0].intValue
        let heatmap_w = heatmap.shape[1].intValue
        let heatmap_h = heatmap.shape[2].intValue
        
        var n_kpoints = (0..<keypoint_number).map { _ -> BodyPoint? in
            return nil
        }
        
        for k in 0..<keypoint_number {
            for i in 0..<heatmap_w {
                for j in 0..<heatmap_h {
                    let index = k*(heatmap_w*heatmap_h) + i*(heatmap_h) + j
                    let confidence = heatmap[index].doubleValue
                    guard confidence > 0 else { continue }
                    if n_kpoints[k] == nil ||
                        (n_kpoints[k] != nil && n_kpoints[k]!.maxConfidence < confidence) {
                        n_kpoints[k] = BodyPoint(maxPoint: CGPoint(x: CGFloat(j), y: CGFloat(i)), maxConfidence: confidence)
                    }
                }
            }
        }
        
        
        // transpose to (1.0, 1.0)
        n_kpoints = n_kpoints.map { kpoint -> BodyPoint? in
            if let kp = kpoint {
                return BodyPoint(maxPoint: CGPoint(x: (kp.maxPoint.x+0.5)/CGFloat(heatmap_w),
                                                   y: (kp.maxPoint.y+0.5)/CGFloat(heatmap_h)),
                                 maxConfidence: kp.maxConfidence)
            } else {
                return nil
            }
        }
        
        return n_kpoints
    }
    
    func showKeypointsDescription(with n_kpoints: [BodyPoint?]) {
        self.tableData = n_kpoints
        self.labelsTableView.reloadData()
    }
}

// MARK: - VideoCaptureDelegate
extension JointViewController: VideoCaptureDelegate {
    func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame pixelBuffer: CVPixelBuffer?, timestamp: CMTime) {
        // 카메라에서 캡쳐된 화면은 pixelBuffer에 담김.
        // Vision 프레임워크에서는 이미지 대신 pixelBuffer를 바로 사용 가능
        if let pixelBuffer = pixelBuffer {
            // start of measure
            self.👨‍🔧.🎬👏()
            
            // predict!
            self.predictUsingVision(pixelBuffer: pixelBuffer)
        }
    }
}

// MARK: - UITableView Data Source
extension JointViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tableData.count// > 0 ? 1 : 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell = tableView.dequeueReusableCell(withIdentifier: "LabelCell", for: indexPath)
        cell.textLabel?.text = Constant.pointLabels[indexPath.row]
        if let body_point = tableData[indexPath.row] {
            let pointText: String = "\(String(format: "%.3f", body_point.maxPoint.x)), \(String(format: "%.3f", body_point.maxPoint.y))"
            cell.detailTextLabel?.text = "(\(pointText)), [\(String(format: "%.3f", body_point.maxConfidence))]"
        } else {
            cell.detailTextLabel?.text = "N/A"
        }
        return cell
    }
}


// MARK: - 📏(Performance Measurement) Delegate
extension JointViewController: 📏Delegate {
    func updateMeasure(inferenceTime: Double, executionTime: Double, fps: Int) {
        //print(executionTime, fps)
        self.inferenceLabel.text = "inference: \(Int(inferenceTime*1000.0)) mm"
        self.etimeLabel.text = "execution: \(Int(executionTime*1000.0)) mm"
        self.fpsLabel.text = "fps: \(fps)"
    }
}
