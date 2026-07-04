import UIKit

enum ReaderScrollRestoration {
    static func offset(for progress: Double, contentHeight: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        let boundedProgress = min(max(progress, 0), 1)
        let maxOffset = max(0, contentHeight - viewportHeight)
        return maxOffset * CGFloat(boundedProgress)
    }

    @MainActor
    static func apply(progress: Double, to scrollView: UIScrollView) {
        scrollView.contentOffset.y = offset(
            for: progress,
            contentHeight: scrollView.contentSize.height,
            viewportHeight: scrollView.bounds.height
        )
    }
}
