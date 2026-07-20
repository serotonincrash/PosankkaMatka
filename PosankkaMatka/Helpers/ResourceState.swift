//
//  ResourceState.swift
//  PosankkaMatka
//
//  Created by sero on 6/4/26.
//

import Foundation
import FoliBusUI

enum ResourceState<T> {
    case loading
    case success(T)
    case failure(Foli.APIError)
}
