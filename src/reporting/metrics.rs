//! Prometheus metrics export

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Metrics data structure
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Metrics {
    pub counters: HashMap<String, u64>,
    pub gauges: HashMap<String, f64>,
    pub histograms: HashMap<String, Vec<f64>>,
}

/// Exports metrics in Prometheus format
pub struct MetricsExporter {
    metrics: Metrics,
    prefix: String,
}

impl MetricsExporter {
    pub fn new(prefix: impl Into<String>) -> Self {
        Self { metrics: Metrics::default(), prefix: prefix.into() }
    }

    /// Increment a counter
    pub fn inc_counter(&mut self, name: &str) {
        let key = format!("{}_{}", self.prefix, name);
        *self.metrics.counters.entry(key).or_insert(0) += 1;
    }

    /// Set a gauge value
    pub fn set_gauge(&mut self, name: &str, value: f64) {
        let key = format!("{}_{}", self.prefix, name);
        self.metrics.gauges.insert(key, value);
    }

    /// Record a histogram value
    pub fn observe_histogram(&mut self, name: &str, value: f64) {
        let key = format!("{}_{}", self.prefix, name);
        self.metrics.histograms.entry(key).or_insert_with(Vec::new).push(value);
    }

    /// Export metrics in Prometheus text format
    pub fn export(&self) -> String {
        let mut output = String::new();

        for (name, value) in &self.metrics.counters {
            output.push_str(&format!("{} {}\n", name, value));
        }

        for (name, value) in &self.metrics.gauges {
            output.push_str(&format!("{} {}\n", name, value));
        }

        output
    }

    pub fn metrics(&self) -> &Metrics {
        &self.metrics
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_counter() {
        let mut exporter = MetricsExporter::new("test");
        exporter.inc_counter("requests");
        exporter.inc_counter("requests");

        assert_eq!(exporter.metrics.counters.get("test_requests"), Some(&2));
    }

    #[test]
    fn test_gauge() {
        let mut exporter = MetricsExporter::new("test");
        exporter.set_gauge("temperature", 23.5);

        assert_eq!(exporter.metrics.gauges.get("test_temperature"), Some(&23.5));
    }
}
