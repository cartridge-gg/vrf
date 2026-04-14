//! Distributed tracing for vrf-server.
//!
//! Mirrors katana's conventions (`dojoengine/katana/crates/tracing`):
//! a layered `tracing-subscriber` with an optional OpenTelemetry OTLP
//! exporter, and a `tower-http` `MakeSpan` that extracts W3C trace
//! context from incoming HTTP headers so spans chain across services.

use std::sync::OnceLock;

use opentelemetry::trace::TracerProvider as _;
use opentelemetry_http::HeaderExtractor;
use opentelemetry_sdk::propagation::TraceContextPropagator;
use opentelemetry_sdk::trace::{RandomIdGenerator, SdkTracerProvider};
use opentelemetry_sdk::Resource;
use tower_http::trace::MakeSpan;
use tracing::Span;
use tracing_opentelemetry::OpenTelemetrySpanExt;
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;
use tracing_subscriber::EnvFilter;

use crate::fmt::LocalTime;

const SERVICE_NAME: &str = "vrf-server";

static PROVIDER: OnceLock<SdkTracerProvider> = OnceLock::new();

/// OTLP exporter configuration.
#[derive(Debug, Clone, Default)]
pub struct OtlpConfig {
    /// OTLP collector endpoint. If `None`, defaults to the OTLP default
    /// (typically `http://localhost:4317`).
    pub endpoint: Option<String>,
}

/// `tower-http` `MakeSpan` that extracts the W3C trace context from inbound
/// HTTP headers and makes it the parent of the new request span.
///
/// If no propagator is globally installed (OTLP disabled) or the headers
/// contain no `traceparent`, the extracted context is empty and the span
/// starts as a fresh root — no panic, no-op.
#[derive(Debug, Clone, Default)]
pub struct OtelMakeSpan;

impl<B> MakeSpan<B> for OtelMakeSpan {
    fn make_span(&mut self, request: &http::Request<B>) -> Span {
        let cx = opentelemetry::global::get_text_map_propagator(|propagator| {
            propagator.extract(&HeaderExtractor(request.headers()))
        });
        let span = tracing::info_span!(
            "http_request",
            method = %request.method(),
            uri = %request.uri(),
        );
        span.set_parent(cx);
        span
    }
}

fn init_otlp_tracer(
    config: &OtlpConfig,
) -> anyhow::Result<(opentelemetry_sdk::trace::Tracer, SdkTracerProvider)> {
    use opentelemetry_otlp::WithExportConfig;

    let mut builder = opentelemetry_otlp::SpanExporter::builder().with_tonic();
    if let Some(endpoint) = &config.endpoint {
        builder = builder.with_endpoint(endpoint.clone());
    }
    let exporter = builder.build()?;

    let provider = SdkTracerProvider::builder()
        .with_id_generator(RandomIdGenerator::default())
        .with_batch_exporter(exporter)
        .with_resource(Resource::builder().with_service_name(SERVICE_NAME).build())
        .build();

    opentelemetry::global::set_text_map_propagator(TraceContextPropagator::new());

    let tracer = provider.tracer(SERVICE_NAME);
    opentelemetry::global::set_tracer_provider(provider.clone());
    Ok((tracer, provider))
}

/// Initialize the global tracing subscriber.
///
/// When `otlp` is `Some`, an OpenTelemetry OTLP (gRPC) exporter is installed
/// alongside the default stdout fmt layer and a W3C text-map propagator.
/// When `otlp` is `None`, only the stdout fmt layer is installed.
pub fn init(otlp: Option<OtlpConfig>) -> anyhow::Result<()> {
    let default_filter = EnvFilter::try_new("info").expect("valid default filter");
    let filter = EnvFilter::try_from_default_env().unwrap_or(default_filter);

    let fmt_layer = tracing_subscriber::fmt::layer().with_timer(LocalTime::new());

    let telemetry_layer = match otlp {
        Some(config) => {
            let (tracer, provider) = init_otlp_tracer(&config)?;
            let _ = PROVIDER.set(provider);
            Some(tracing_opentelemetry::layer().with_tracer(tracer))
        }
        None => None,
    };

    tracing_subscriber::registry()
        .with(filter)
        .with(telemetry_layer)
        .with(fmt_layer)
        .init();

    Ok(())
}

/// Flush and shut down the OTLP tracer provider, if one was installed.
///
/// Call this on graceful shutdown so the batch exporter flushes tail spans
/// before the process exits. No-op when OTLP wasn't enabled.
pub fn shutdown() {
    if let Some(provider) = PROVIDER.get() {
        let _ = provider.shutdown();
    }
}

#[cfg(test)]
mod tests {
    use opentelemetry::trace::TraceContextExt;
    use opentelemetry::Context;

    use super::*;

    /// Ensure the global W3C propagator is installed for these tests.
    /// Tests share process state, so this is idempotent.
    fn ensure_propagator() {
        static ONCE: std::sync::Once = std::sync::Once::new();
        ONCE.call_once(|| {
            opentelemetry::global::set_text_map_propagator(TraceContextPropagator::new());
        });
    }

    /// Extract the parent context directly from request headers the same way
    /// `OtelMakeSpan::make_span` does, so we can assert on propagator output
    /// without needing a full `tracing_opentelemetry` layer installed.
    fn extract_parent<B>(req: &http::Request<B>) -> Context {
        opentelemetry::global::get_text_map_propagator(|propagator| {
            propagator.extract(&HeaderExtractor(req.headers()))
        })
    }

    #[test]
    fn make_span_without_traceparent_is_root() {
        ensure_propagator();
        let req = http::Request::builder().uri("/info").body(()).unwrap();

        // Call make_span to exercise the real code path (must not panic).
        let _ = OtelMakeSpan.make_span(&req);

        // No traceparent header → propagator returns an empty context.
        let cx = extract_parent(&req);
        let otel_span = cx.span();
        assert!(!otel_span.span_context().is_valid());
    }

    #[test]
    fn make_span_with_valid_traceparent_is_child() {
        ensure_propagator();
        let trace_id_hex = "0af7651916cd43dd8448eb211c80319c";
        let req = http::Request::builder()
            .uri("/proof")
            .header(
                "traceparent",
                format!("00-{trace_id_hex}-b7ad6b7169203331-01"),
            )
            .body(())
            .unwrap();

        let _ = OtelMakeSpan.make_span(&req);

        let cx = extract_parent(&req);
        let otel_span = cx.span();
        let sc = otel_span.span_context();
        assert!(sc.is_valid(), "remote span context should be valid");
        assert_eq!(sc.trace_id().to_string(), trace_id_hex);
    }

    #[test]
    fn make_span_with_malformed_traceparent_does_not_panic() {
        ensure_propagator();
        let req = http::Request::builder()
            .uri("/info")
            .header("traceparent", "garbage-not-a-valid-header")
            .body(())
            .unwrap();

        // Must not panic.
        let _ = OtelMakeSpan.make_span(&req);

        let cx = extract_parent(&req);
        let otel_span = cx.span();
        assert!(!otel_span.span_context().is_valid());
    }
}
