//
//  ViewController.swift
//  Selfie-share
//
//  Created by Michele Galvagno on 06/05/2019.
//  Copyright © 2019 Michele Galvagno. All rights reserved.
//

import MultipeerConnectivity
import UIKit

class ViewController: UICollectionViewController, UINavigationControllerDelegate, UIImagePickerControllerDelegate, MCSessionDelegate, MCBrowserViewControllerDelegate {
    // MARK: - Properties
    var images = [UIImage]()
    
    var peerID = MCPeerID(displayName: UIDevice.current.name)
    var mcSession: MCSession?
    var mcAdvertiserAssistant: MCAdvertiserAssistant?

    // MARK: - View management
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Selfie share"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .camera, target: self, action: #selector(importPicture))
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(showConnectionPrompt))
        
        let flexibleSpaceButton = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil)
        let messageButton = UIBarButtonItem(title: "Send message", style: .plain, target: self, action: #selector(writeMessage))
        toolbarItems = [flexibleSpaceButton, messageButton]
        
        mcSession = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        mcSession?.delegate = self
    }
    
    // MARK: - Collection View Data Source
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return images.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ImageView", for: indexPath)
        
        if let imageView = cell.viewWithTag(1000) as? UIImageView {
            imageView.image = images[indexPath.row]
        }
        
        return cell
    }

    // MARK: - Picker controller methods
    @objc func importPicture() {
        let picker = UIImagePickerController()
        picker.allowsEditing = true
        picker.delegate = self
        present(picker, animated: true)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        guard let image = info[.editedImage] as? UIImage else { return }
        
        dismiss(animated: true)
        
        images.insert(image, at: 0)
        collectionView.reloadData()
        
        // 1. check that we have an active session
        guard let mcSession = mcSession else { return }
        
        // 2. check if there are any peers to send to
        if mcSession.connectedPeers.count > 0 {
            // 3. convert the new image to a Data object
            if let imageData = image.pngData() {
                // 4. send it to all peers, ensuring it gets delivered
                do {
                    try mcSession.send(imageData, toPeers: mcSession.connectedPeers, with: .reliable)
                } catch {
                    // 5. show an error message if there's a problem
                    let errorAC = UIAlertController(title: "Send error", message: error.localizedDescription, preferredStyle: .alert)
                    errorAC.addAction(UIAlertAction(title: "OK", style: .default))
                    
                    present(errorAC, animated: true)
                }
            }
        }
    }
    
    @objc func writeMessage() {
        let messageAC = UIAlertController(title: "Send a message", message: "Type your message and hit Send to share it with your peers!", preferredStyle: .alert)
        messageAC.addTextField()
        
        let sendAction = UIAlertAction(title: "Send", style: .default) { [weak self, weak messageAC] action in
            guard let message = messageAC?.textFields?[0].text else { return }
            guard let mcSession = self?.mcSession else { return }
            
            let messageData = Data(message.utf8)
            do {
                try self?.mcSession?.send(messageData, toPeers: mcSession.connectedPeers, with: .reliable)
            } catch {
                let errorAC = UIAlertController(title: "Send error", message: error.localizedDescription, preferredStyle: .alert)
                errorAC.addAction(UIAlertAction(title: "OK", style: .default))
                
                self?.present(errorAC, animated: true)
            }
        }
        
        messageAC.addAction(sendAction)
        messageAC.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(messageAC, animated: true)
    }

    // MARK: - P2P Methods
    @objc func showConnectionPrompt() {
        let connectionAC = UIAlertController(title: "Connect to others", message: nil, preferredStyle: .alert)
        connectionAC.addAction(UIAlertAction(title: "Host a session", style: .default, handler: startHosting))
        connectionAC.addAction(UIAlertAction(title: "Join a session", style: .default, handler: joinSession))
        connectionAC.addAction(UIAlertAction(title: "Leave the session", style: .default, handler: leaveSession))
        connectionAC.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(connectionAC, animated: true)
    }
    
    func startHosting(action: UIAlertAction) {
        guard let mcSession = mcSession else { return }
        
        mcAdvertiserAssistant = MCAdvertiserAssistant(serviceType: "hws-project25", discoveryInfo: nil, session: mcSession)
        mcAdvertiserAssistant?.start()
    }
    
    func joinSession(action: UIAlertAction) {
        guard let mcSession = mcSession else { return }

        let mcBrowser = MCBrowserViewController(serviceType: "hws-project25", session: mcSession)
        mcBrowser.delegate = self
        
        present(mcBrowser, animated: true)
    }

    func leaveSession(action: UIAlertAction) {
        guard let mcSession = mcSession else { return }
        
        mcSession.disconnect()
    }
    
    // MARK: - MCSession delegate methods
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected: print("Connected: \(peerID.displayName)")
        case .connecting: print("Connecting: \(peerID.displayName)")
        case .notConnected:
            DispatchQueue.main.async { [weak self] in
                let notConnectedAC = UIAlertController(title: "Disconnected!", message: "\(peerID.displayName) has left the network", preferredStyle: .alert)
                notConnectedAC.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                self?.present(notConnectedAC, animated: true, completion: nil)
            }
            
            print("Not connected: \(peerID.displayName)")
        @unknown default: print("Unkown state received: \(peerID.displayName)")
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            if let image = UIImage(data: data) {
                self?.images.insert(image, at: 0)
                self?.collectionView.reloadData()
            } else {
                let message = String(decoding: data, as: UTF8.self)
                
                let receivedMessageAC = UIAlertController(title: "New incoming message", message: "\(peerID.displayName) sent the following message:\n\(message)", preferredStyle: .alert)
                receivedMessageAC.addAction(UIAlertAction(title: "Got it!", style: .default, handler: nil))
                
                receivedMessageAC.addAction(UIAlertAction(title: "Reply", style: .default, handler: { [weak self] (action) in
                    self?.writeMessage()
                }))
                
                self?.present(receivedMessageAC, animated: true)
            }
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // leave empty
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // leave empty
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // leave empty
    }
    
    // MARK: - MCBrowserVC delegate methods
    func browserViewControllerDidFinish(_ browserViewController: MCBrowserViewController) {
        dismiss(animated: true)
    }
    
    func browserViewControllerWasCancelled(_ browserViewController: MCBrowserViewController) {
        dismiss(animated: true)
    }
}

