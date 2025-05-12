//
//  DeploymentAddress.swift
//  tic_tac_toe_ios_ethereum
//
//  Created by Agent Malone on 5/13/25.
//

import Foundation

// This structure matches the layout of your deployment_output_*.json files
struct DeploymentAddresses: Codable {
    let gameImplementationAddress: String? // Must match JSON key exactly or use CodingKeys
    let factoryAddress: String?            // Must match JSON key exactly or use CodingKeys

    // If your JSON keys look like "factory_address", uncomment this section:
    /*
    enum CodingKeys: String, CodingKey {
        case gameImplementationAddress = "game_implementation_address" // Example if JSON uses snake_case
        case factoryAddress = "factory_address"
    }
    */
}
