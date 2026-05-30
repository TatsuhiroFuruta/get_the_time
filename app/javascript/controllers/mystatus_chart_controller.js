import { Controller } from "@hotwired/stimulus"
import {
  Chart,
  BarController,
  BarElement,
  LineController,
  LineElement,
  PointElement,
  CategoryScale,
  LinearScale,
  Tooltip,
  Legend,
  Filler
} from "chart.js"

Chart.register(
  BarController,
  BarElement,
  LineController,
  LineElement,
  PointElement,
  CategoryScale,
  LinearScale,
  Tooltip,
  Legend,
  Filler
)

// Connects to data-controller="mystatus-chart"
export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    type: String,
    labels: Array,
    data: Array,
    label: String,
    color: { type: String, default: "#facc15" },
    yMax: { type: Number, default: 0 },
    yLabelMax: { type: Number, default: 0 }
  }

  connect() {
    this.chart = new Chart(this.canvasTarget, {
      type: this.typeValue,
      data: {
        labels: this.labelsValue,
        datasets: [{
          label: this.labelValue,
          data: this.dataValue,
          backgroundColor: this.colorValue,
          borderColor: this.colorValue,
          borderWidth: 2,
          fill: false,
          tension: 0.2,
          spanGaps: true,
          pointRadius: 3
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: true, position: "top" }
        },
        scales: {
          y: {
            beginAtZero: true,
            max: this.yMaxValue > 0 ? this.yMaxValue : undefined,
            ticks: {
              // yLabelMax を超える値はラベル非表示（軸自体は yMax まで描画される）
              callback: (value) => (this.yLabelMaxValue > 0 && value > this.yLabelMaxValue) ? "" : value
            }
          }
        }
      }
    })
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  }
}
