import Foundation

// The reasons a request to Claude can fail.
enum ClaudeError: Error, Equatable {
    case noKey          // no API key has been set yet
    case offline        // no internet connection
    case unauthorized   // the API key was not accepted
    case noCredit       // the Anthropic account has no credit
    case busy           // rate limited or overloaded
    case refused        // the model declined to read the page
    case tooLarge       // the page is too big to send
    case rejected       // the API did not accept the request itself
    case failed         // anything else

    // What the user is told when this error stops a conversion.
    var message: String {
        switch self {
        case .noKey: return "Add an Anthropic API key first: choose Set API key… from the Inkdown menu."
        case .offline: return "No internet connection. Nothing was written."
        case .unauthorized: return "The API key was not accepted. Set it again from the Inkdown menu."
        case .noCredit: return "Your Anthropic account has no credit. Add credit in the Anthropic Console."
        case .busy: return "Claude is busy right now. Try again in a few minutes."
        case .refused: return "Claude declined to read this PDF."
        case .tooLarge: return "A page of this PDF is too large to send."
        case .rejected: return "Claude did not accept the request. Inkdown may need an update. Nothing was written."
        case .failed: return "Something went wrong while talking to Claude. Try again."
        }
    }
}

// The reasons a whole conversion can fail.
enum ConversionError: Error, Equatable {
    case cannotOpen             // the file is missing or is not a PDF
    case locked                 // the PDF needs a password
    case empty                  // the PDF has no pages
    case stopped(ClaudeError)   // Claude could not be reached or refused the key
    case cancelled              // the user chose Cancel
    case cannotWrite            // the Markdown file could not be saved
    case nothingRead            // not a single page could be read

    // What the user is told.
    var message: String {
        switch self {
        case .cannotOpen: return "This file could not be opened as a PDF."
        case .locked: return "This PDF is password-protected."
        case .empty: return "This PDF has no pages."
        case .stopped(let error): return error.message
        case .cancelled: return "The conversion was cancelled."
        case .cannotWrite: return "The Markdown file could not be saved."
        case .nothingRead: return "None of the pages could be read, so no file was written. Try again in a few minutes."
        }
    }
}

// What became of one page.
enum PageResult: Equatable {
    case text(String)   // the page's text as Markdown
    case blank          // nothing was on the page
    case unreadable     // the page could not be read
}
