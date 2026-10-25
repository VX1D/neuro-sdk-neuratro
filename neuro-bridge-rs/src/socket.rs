use super::*;

pub(crate) const WS_CONNECT_TIMEOUT_SECS: u64 = 10;
pub(crate) const WS_WRITE_TIMEOUT_SECS: u64 = 5;
pub(crate) const WS_CLOSE_TIMEOUT_SECS: u64 = 2;
pub(crate) const SESSION_TEARDOWN_TIMEOUT_SECS: u64 = 3;

async fn within<T, E>(
    secs: u64,
    what: &'static str,
    step: impl std::future::Future<Output = Result<T, E>>,
) -> Result<T>
where
    E: std::error::Error + Send + Sync + 'static,
{
    time::timeout(Duration::from_secs(secs), step)
        .await
        .with_context(|| format!("websocket {what} deadline exceeded"))?
        .with_context(|| format!("websocket {what} failed"))
}

pub(crate) async fn websocket_send<S>(sink: &mut S, message: Message) -> Result<()>
where
    S: futures_util::Sink<Message> + Unpin,
    S::Error: std::error::Error + Send + Sync + 'static,
{
    within(WS_WRITE_TIMEOUT_SECS, "feed", sink.feed(message)).await?;
    websocket_flush(sink).await
}

pub(crate) async fn websocket_flush<S>(sink: &mut S) -> Result<()>
where
    S: futures_util::Sink<Message> + Unpin,
    S::Error: std::error::Error + Send + Sync + 'static,
{
    within(WS_WRITE_TIMEOUT_SECS, "flush", sink.flush()).await
}

pub(crate) async fn websocket_close<S>(sink: &mut S) -> Result<()>
where
    S: futures_util::Sink<Message> + Unpin,
    S::Error: std::error::Error + Send + Sync + 'static,
{
    within(WS_CLOSE_TIMEOUT_SECS, "close", sink.close()).await
}

pub(crate) struct SessionTasks {
    pub(crate) tx: tokio::task::JoinHandle<()>,
    pub(crate) rx: Option<tokio::task::JoinHandle<()>>,
}

impl SessionTasks {
    pub(crate) fn tx_is_finished(&self) -> bool {
        self.tx.is_finished()
    }

    pub(crate) fn rx_is_finished(&self) -> bool {
        self.rx
            .as_ref()
            .is_some_and(tokio::task::JoinHandle::is_finished)
    }

    pub(crate) fn abort(&self) {
        self.tx.abort();
        if let Some(task) = &self.rx {
            task.abort();
        }
    }

    pub(crate) async fn stop(mut self) {
        self.abort();
        let _ = time::timeout(
            Duration::from_secs(SESSION_TEARDOWN_TIMEOUT_SECS),
            &mut self.tx,
        )
        .await;
        if let Some(task) = self.rx.take() {
            let _ = time::timeout(Duration::from_secs(SESSION_TEARDOWN_TIMEOUT_SECS), task).await;
        }
    }
}
impl Drop for SessionTasks {
    fn drop(&mut self) {
        self.abort();
    }
}

pub(crate) fn tls_connector() -> Result<tokio_tungstenite::Connector> {
    let mut roots = rustls::RootCertStore::empty();
    roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    let config = rustls::ClientConfig::builder_with_provider(Arc::new(
        rustls::crypto::ring::default_provider(),
    ))
    .with_safe_default_protocol_versions()
    .context("configure TLS protocol versions")?
    .with_root_certificates(roots)
    .with_no_client_auth();
    Ok(tokio_tungstenite::Connector::Rustls(Arc::new(config)))
}

pub(crate) async fn connect_websocket(url: &str) -> Result<WsStream> {
    let websocket_config = WebSocketConfig::default()
        .max_message_size(Some(MAX_INBOUND_FRAME_BYTES))
        .max_frame_size(Some(MAX_INBOUND_FRAME_BYTES));
    let secure = url
        .get(..6)
        .is_some_and(|scheme| scheme.eq_ignore_ascii_case("wss://"));
    let connector = if secure { Some(tls_connector()?) } else { None };
    let (ws_stream, _) = time::timeout(
        Duration::from_secs(WS_CONNECT_TIMEOUT_SECS),
        connect_async_tls_with_config(url, Some(websocket_config), true, connector),
    )
    .await
    .context("connect websocket deadline exceeded")?
    .context("connect websocket")?;
    Ok(ws_stream)
}
