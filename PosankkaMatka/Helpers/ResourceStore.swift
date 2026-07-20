//
//  ResourceStore.swift
//  PosankkaMatka
//
//  Created by sero on 17/7/26.
//

import FoliBusAPI
struct ResourceStore<T> {
    #warning("TODO do up this resource store, needs async load/fetch")
    
    var loadState: ResourceState<T> = .loading
}
