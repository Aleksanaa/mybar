import QtQuick

Canvas {
    id: chart
    // 暴露给外部的接口
    property real value: 0        // 当前数值 (0.0 - 1.0)
    property color lineColor: Theme.accent
    property int maxPoints: 40

    // 内部私有记忆
    property var _history: []

    // 核心逻辑：当外部传入的数值变化时，自动更新历史记录
    onValueChanged: {
        let data = _history;
        data.push(value);
        if (data.length > maxPoints) data.shift();
        _history = data;
        chart.requestPaint(); // 触发重绘
    }

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        if (_history.length < 2) return;

        let stepX = width / (maxPoints - 1);
    
        ctx.beginPath();
        ctx.strokeStyle = lineColor;
        ctx.lineWidth = 2;
        for (let i = 0; i < _history.length; i++) {
            let x = i * stepX;
            let y = height - (_history[i] * height);
            if (i === 0) ctx.moveTo(x, y);
            else ctx.lineTo(x, y);
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
