import QtQuick

Canvas {
    id: chart
    // Interface exposed to the outside
    property real value: 0        // Current value
    property color lineColor: Theme.accent
    property int maxPoints: 40
    property bool autoScale: false
    property bool inverted: false

    // Internal private memory
    property var _history: []
    property bool enabled: true

    Timer {
        interval: 1000
        running: chart.enabled && chart.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            let data = _history;
            data.push(value);
            if (data.length > maxPoints)
                data.shift();
            _history = data;
            chart.requestPaint();
        }
    }

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        if (_history.length < 2)
            return;

        let stepX = width / (maxPoints - 1);
        let maxValue = 1.0;
        if (autoScale) {
            maxValue = Math.max(..._history);
            if (maxValue <= 0) maxValue = 1.0;
        }

        ctx.beginPath();
        ctx.strokeStyle = lineColor;
        ctx.lineWidth = 2;
        for (let i = 0; i < _history.length; i++) {
            let x = i * stepX;
            let normalizedValue = _history[i] / maxValue;
            let y = inverted ? (normalizedValue * height) : (height - (normalizedValue * height));
            if (i === 0)
                ctx.moveTo(x, y);
            else
                ctx.lineTo(x, y);
        }
        ctx.stroke();

        ctx.lineTo((_history.length - 1) * stepX, inverted ? 0 : height);
        ctx.lineTo(0, inverted ? 0 : height);
        ctx.closePath();
        let grad = ctx.createLinearGradient(0, inverted ? height : 0, 0, inverted ? 0 : height);
        grad.addColorStop(0, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.3));
        grad.addColorStop(1, "transparent");
        ctx.fillStyle = grad;
        ctx.fill();
    }
}
