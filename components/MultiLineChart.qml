import QtQuick

Canvas {
    id: chart
    // Interface exposed to the outside
    property var values: []        // Array of current values [val1, val2, ...]
    property var lineColors: []    // Array of colors [#color1, #color2, ...]
    property int maxPoints: 40
    property bool autoScale: false

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
            let currentValues = values;

            // Initialize history if needed
            if (data.length === 0) {
                for (let i = 0; i < currentValues.length; i++) {
                    data.push(new Array(maxPoints).fill(0));
                }
            }

            // Push new values and shift
            for (let i = 0; i < currentValues.length; i++) {
                data[i].push(currentValues[i]);
                if (data[i].length > maxPoints)
                    data[i].shift();
            }

            _history = data;
            chart.requestPaint();
        }
    }

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        if (_history.length === 0 || _history[0].length < 2)
            return;

        let stepX = width / (maxPoints - 1);
        let maxValue = 1.0;

        if (autoScale) {
            let currentMax = 0;
            for (let j = 0; j < _history.length; j++) {
                currentMax = Math.max(currentMax, ..._history[j]);
            }
            maxValue = currentMax;
            if (maxValue <= 0)
                maxValue = 1.0;
            else
                maxValue *= 1.1; // Add 10% headroom
        }

        for (let j = 0; j < _history.length; j++) {
            let color = (lineColors && lineColors.length > j) ? lineColors[j] : Theme.accent;
            let history = _history[j];

            ctx.beginPath();
            ctx.strokeStyle = color;
            ctx.lineWidth = 1.5;

            for (let i = 0; i < history.length; i++) {
                let x = i * stepX;
                let normalizedValue = history[i] / maxValue;
                let y = height - (normalizedValue * height);
                if (i === 0)
                    ctx.moveTo(x, y);
                else
                    ctx.lineTo(x, y);
            }
            ctx.stroke();

            // Fill area with very subtle gradient
            ctx.lineTo((history.length - 1) * stepX, height);
            ctx.lineTo(0, height);
            ctx.closePath();
            let grad = ctx.createLinearGradient(0, 0, 0, height);
            grad.addColorStop(0, Qt.rgba(color.r, color.g, color.b, 0.1));
            grad.addColorStop(1, "transparent");
            ctx.fillStyle = grad;
            ctx.fill();
        }
    }
}
