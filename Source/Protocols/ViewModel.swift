//
//  Created by Pierluigi Cifani on 03/05/16.
//  Copyright © 2016 Blurred Software SL. All rights reserved.
//

import UIKit
import BSWFoundation
import Deferred

//MARK:- Protocols

public protocol ViewModelConfigurable {
    associatedtype VM
    func configureFor(viewModel: VM)
}

public protocol ViewModelReusable: ViewModelConfigurable {
    static var reuseType: ReuseType { get }
    static var reuseIdentifier: String { get }
}

public protocol AsyncViewModelPresenter: ViewModelConfigurable {
    var dataProvider: Task<VM>! { get set }
}

extension AsyncViewModelPresenter where Self: UIViewController {
    
    public init(dataProvider: Task<VM>) {
        self.init(nibName: nil, bundle: nil)
        self.dataProvider = dataProvider

        dataProvider.upon(.main) { [weak self] result in
            guard let strongSelf = self else { return }
            let _ = strongSelf.view //This touches the view, making sure that the outlets are set
            switch result {
            case .failure(let error):
                #if DEBUG
                    strongSelf.showErrorMessage("Error fetching data", error: error)
                #else
                    print("AsyncViewModelPresenter error: \(error)")
                #endif
            case .success(let viewModel):
                guard let _ = strongSelf.view else { return }
                strongSelf.configureFor(viewModel: viewModel)
            }
        }
    }
}

//MARK:- Extensions

extension ViewModelReusable where Self: UICollectionViewCell {
    public static var reuseIdentifier: String {
        return NSStringFromClass(self).components(separatedBy: ".").last!
    }
    
    public static var reuseType: ReuseType {
        return .classReference(Self)
    }
}

//MARK:- Types

public enum ReuseType {
    case nib(UINib)
    case classReference(AnyClass)
}

