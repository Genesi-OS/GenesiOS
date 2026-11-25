// The page stack, as a NAMED type. It has to be named: `pageStack.initialPage:`
// is resolved against the property's declared type, and a bare QtObject has no
// such property, so the assignment is rejected at load time.
import QtQuick
QtObject {
    property Item initialPage
    property Item currentItem: initialPage
    property int depth: initialPage ? 1 : 0
    signal pageRequested(var page)
    function push(p) { pageRequested(p) }
    function pop() {}
    function clear() {}
}
