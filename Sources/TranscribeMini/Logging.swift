import Foundation
import Darwin

func tmLog(_ message: String) {
    fputs(message + "\n", stderr)
    fflush(stderr)
}
