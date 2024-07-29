//
//  ColorExtensions.swift
//  Joyride
//
//  Created by Maximillian Ludwick on 7/23/24.
//

import SwiftUI
import MapboxNavigationUIKit

extension Color {
    static let dynamicBackground = Color(UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor.black
        default:
            return UIColor.white
        }
    })
    
    static let dynamicText = Color(UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor.white
        default:
            return UIColor.black
        }
    })
}

extension UIColor {
    static let dynamicNavigationBackground: UIColor = {
        UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return .black
            default:
                return .white
            }
        }
    }()
    
    static let dynamicNavigationText: UIColor = {
        UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return .white
            default:
                return .black
            }
        }
    }()
}
