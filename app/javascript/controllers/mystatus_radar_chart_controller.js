import { Controller } from "@hotwired/stimulus"
import {
  Chart,
  RadarController,
  RadialLinearScale,
  PointElement,
  LineElement,
  Filler,
  Tooltip,
  Legend
} from "chart.js"

Chart.register(
  RadarController,
  RadialLinearScale,
  PointElement,
  LineElement,
  Filler,
  Tooltip,
  Legend
)

// Connects to data-controller="mystatus-radar-chart"
export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    labels: Array,
    data: Array,
    label: { type: String, default: "評価" },
    color: { type: String, default: "#34d399" },
    fillColor: { type: String, default: "rgba(52, 211, 153, 0.2)" },
    max: { type: Number, default: 5 },
    showLegend: { type: Boolean, default: false }
  }

  connect() {
    this.chart = new Chart(this.canvasTarget, {
      type: "radar",
      data: {
        labels: this.labelsValue,
        datasets: [{
          label: this.labelValue,
          data: this.dataValue,
          backgroundColor: this.fillColorValue,
          borderColor: this.colorValue,
          pointBackgroundColor: this.colorValue,
          borderWidth: 2
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: this.showLegendValue, position: "top" }
        },
        scales: {
          r: {
            min: 0,
            max: this.maxValue,
            ticks: { stepSize: 1 },
            pointLabels: { font: { size: 13 } }
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
