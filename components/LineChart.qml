import QtQuick

Canvas {
    id: chart
    // Interface exposed to the outside
    property real value: 0        // Current value (0.0 - 1.0)
    property color lineColor: Theme.accent
    property int maxPoints: 40

    // Internal private memory
    property var _history: []

    // Core logic: when the external value changes, the history is automatically updated
    onValueChanged: {
        let data = _history;
        data.push(value);
        if (data.length > maxPoints)
            data.shift();
        _history = data;
        chart.requestPaint(); // Trigger repaint
    }

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        if (_history.length < 2)
            return;

        let stepX = width / (maxPoints - 1);

        ctx.beginPath();
        ctx.strokeStyle = lineColor;
        ctx.lineWidth = 2;
        for (let i = 0; i < _history.length; i++) {
            let x = i * stepX;
            let y = height - (_history[i] * height);
            if (i === 0)
                ctx.moveTo(x, y);
            else
                ctx.lineTo(x, y);
        }
        ctx.stroke();

        ctx.lineTo((_history.length - 1) * stepX, height);
        ctx.lineTo(0, height);
        ctx.closePath();
        let grad = ctx.createLinearGradient(0, 0, 0, height);
        grad.addColorStop(0, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.3));
        grad.addColorStop(1, "transparent");
        ctx.fillStyle = grad;
        ctx.fill();
    }
}
