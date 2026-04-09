// Prevents additional console window on Windows in release
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::{Emitter, Manager};
use tauri::menu::{MenuBuilder, MenuItemBuilder};
use tauri::tray::TrayIconBuilder;

#[tauri::command]
fn move_cat_window(app: tauri::AppHandle, label: String, x: i32, y: i32) -> Result<(), String> {
    if let Some(window) = app.get_webview_window(&label) {
        window.set_position(tauri::LogicalPosition::new(x, y))
            .map_err(|e: tauri::Error| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
fn get_screen_size(app: tauri::AppHandle) -> Result<(u32, u32), String> {
    let window = app.get_webview_window("main").ok_or("no main window")?;
    let monitor = window.current_monitor()
        .map_err(|e: tauri::Error| e.to_string())?
        .ok_or("no monitor")?;
    let size = monitor.size();
    let scale = monitor.scale_factor();
    Ok(((size.width as f64 / scale) as u32, (size.height as f64 / scale) as u32))
}

#[tauri::command]
fn get_taskbar_height() -> u32 {
    #[cfg(target_os = "macos")]
    { 70 }
    #[cfg(target_os = "windows")]
    { 48 }
    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    { 40 }
}

#[tauri::command]
fn get_mouse_position(app: tauri::AppHandle) -> Result<(i32, i32), String> {
    #[cfg(target_os = "macos")]
    {
        let _ = &app; // suppress unused warning on macOS
        use objc2::msg_send;
        #[repr(C)]
        #[derive(Copy, Clone)]
        struct NSPoint { x: f64, y: f64 }
        unsafe impl objc2::Encode for NSPoint {
            const ENCODING: objc2::Encoding = objc2::Encoding::Struct(
                "CGPoint", &[objc2::Encoding::Double, objc2::Encoding::Double]
            );
        }
        unsafe {
            let point: NSPoint = msg_send![objc2::class!(NSEvent), mouseLocation];
            return Ok((point.x as i32, point.y as i32));
        }
    }
    #[cfg(not(target_os = "macos"))]
    {
        if let Some(window) = app.get_webview_window("main") {
            if let Ok(pos) = window.cursor_position() {
                return Ok((pos.x as i32, pos.y as i32));
            }
        }
        Err("cannot get mouse position".into())
    }
}

#[tauri::command]
fn resize_window(app: tauri::AppHandle, label: String, width: u32, height: u32) -> Result<(), String> {
    if let Some(window) = app.get_webview_window(&label) {
        window.set_size(tauri::LogicalSize::new(width, height))
            .map_err(|e: tauri::Error| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
fn hide_settings(app: tauri::AppHandle) -> Result<(), String> {
    if let Some(window) = app.get_webview_window("settings") {
        window.hide().map_err(|e: tauri::Error| e.to_string())?;
    }
    Ok(())
}

/// Emit a settings-changed event to the main window so it can reload config.
/// Used because localStorage events don't propagate between Tauri webviews.
#[tauri::command]
fn notify_settings_changed(app: tauri::AppHandle) -> Result<(), String> {
    if let Some(window) = app.get_webview_window("main") {
        window.emit("settings-changed", ()).map_err(|e: tauri::Error| e.to_string())?;
    }
    Ok(())
}

const OLLAMA_URL: &str = "http://localhost:11434";

#[tauri::command]
async fn ollama_models() -> Result<Vec<String>, String> {
    let url = format!("{}/api/tags", OLLAMA_URL);
    let resp = reqwest::get(&url).await.map_err(|e| e.to_string())?;
    let json: serde_json::Value = resp.json().await.map_err(|e| e.to_string())?;
    let models = json["models"]
        .as_array()
        .map(|arr| {
            arr.iter()
                .filter_map(|m| m["name"].as_str().map(String::from))
                .collect()
        })
        .unwrap_or_default();
    Ok(models)
}

#[tauri::command]
async fn ollama_chat(
    model: String,
    messages: Vec<serde_json::Value>,
) -> Result<String, String> {
    let url = format!("{}/api/chat", OLLAMA_URL);
    let body = serde_json::json!({
        "model": model,
        "messages": messages,
        "stream": false
    });
    let client = reqwest::Client::new();
    let resp = client
        .post(&url)
        .json(&body)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        return Err(format!("Ollama HTTP {}", resp.status()));
    }
    let json: serde_json::Value = resp.json().await.map_err(|e| e.to_string())?;
    let content = json["message"]["content"]
        .as_str()
        .unwrap_or("")
        .to_string();
    Ok(content)
}

#[cfg(target_os = "macos")]
unsafe fn set_draws_background_recursive(
    view: *mut objc2::runtime::AnyObject,
    sel: objc2::runtime::Sel,
) {
    use objc2::msg_send;
    if view.is_null() { return; }

    let responds: bool = msg_send![view, respondsToSelector: sel];
    if responds {
        let _: () = msg_send![view, setDrawsBackground: false];
    }

    let subviews: *mut objc2::runtime::AnyObject = msg_send![view, subviews];
    if subviews.is_null() { return; }
    let count: usize = msg_send![subviews, count];
    for i in 0..count {
        let child: *mut objc2::runtime::AnyObject = msg_send![subviews, objectAtIndex: i];
        set_draws_background_recursive(child, sel);
    }
}

#[cfg(target_os = "macos")]
fn force_transparent(window: &tauri::WebviewWindow) {
    use objc2::msg_send;
    use objc2::sel;
    use objc2::runtime::AnyObject;

    if let Ok(ns_window_ptr) = window.ns_window() {
        let ns_window = ns_window_ptr as *mut AnyObject;
        unsafe {
            let clear_color: *mut AnyObject = msg_send![
                objc2::class!(NSColor), clearColor
            ];
            let _: () = msg_send![ns_window, setBackgroundColor: clear_color];
            let _: () = msg_send![ns_window, setOpaque: false];
            let _: () = msg_send![ns_window, setHasShadow: false];
        }
    }

    if let Ok(ns_view_ptr) = window.ns_view() {
        let ns_view = ns_view_ptr as *mut AnyObject;
        unsafe {
            let draws_sel = sel!(setDrawsBackground:);
            set_draws_background_recursive(ns_view, draws_sel);
        }
    }
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            move_cat_window,
            get_screen_size,
            get_taskbar_height,
            get_mouse_position,
            resize_window,
            hide_settings,
            notify_settings_changed,
            ollama_models,
            ollama_chat,
        ])
        .setup(|app| {
            let main_window = app.get_webview_window("main").unwrap();

            #[cfg(target_os = "macos")]
            force_transparent(&main_window);

            main_window.show().unwrap();

            // Build tray menu
            let settings_item = MenuItemBuilder::with_id("settings", "Settings...")
                .build(app)?;
            let quit_item = MenuItemBuilder::with_id("quit", "Quit")
                .build(app)?;
            let tray_menu = MenuBuilder::new(app)
                .item(&settings_item)
                .separator()
                .item(&quit_item)
                .build()?;

            let _tray = TrayIconBuilder::new()
                .menu(&tray_menu)
                .icon(app.default_window_icon().cloned().unwrap())
                .icon_as_template(true)
                .on_menu_event(|app, event| {
                    match event.id().as_ref() {
                        "settings" => {
                            if let Some(window) = app.get_webview_window("settings") {
                                let _ = window.show();
                                let _ = window.set_focus();
                            }
                        }
                        "quit" => {
                            app.exit(0);
                        }
                        _ => {}
                    }
                })
                .build(app)?;

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running CATAI");
}
