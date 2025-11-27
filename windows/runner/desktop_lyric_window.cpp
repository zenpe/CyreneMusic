#include "desktop_lyric_window.h"
#include <dwmapi.h>
#include <gdiplus.h>
#include <algorithm>

#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "gdiplus.lib")

namespace {
const wchar_t kWindowClassName[] = L"DESKTOP_LYRIC_WINDOW";
const int kDefaultFontSize = 32;
const DWORD kDefaultTextColor = 0xFFFFFFFF;  // White
const DWORD kDefaultStrokeColor = 0xFF000000;  // Black
const int kDefaultStrokeWidth = 2;
const int kWindowWidth = 800;
const int kWindowHeight = 100;
const int kControlPanelHeight = 180;  // Height when showing controls
const int kHoverDelay = 300;  // ms to wait before showing controls

// GDI+ initialization
ULONG_PTR gdiplusToken = 0;

void InitGdiPlus() {
  if (gdiplusToken == 0) {
    Gdiplus::GdiplusStartupInput gdiplusStartupInput;
    Gdiplus::GdiplusStartup(&gdiplusToken, &gdiplusStartupInput, nullptr);
  }
}

void ShutdownGdiPlus() {
  if (gdiplusToken != 0) {
    Gdiplus::GdiplusShutdown(gdiplusToken);
    gdiplusToken = 0;
  }
}

}  // namespace

DesktopLyricWindow::DesktopLyricWindow()
    : hwnd_(nullptr),
      lyric_text_(L""),
      song_title_(L""),
      song_artist_(L""),
      album_cover_url_(L""),
      font_size_(kDefaultFontSize),
      text_color_(kDefaultTextColor),
      stroke_color_(kDefaultStrokeColor),
      stroke_width_(kDefaultStrokeWidth),
      is_draggable_(true),
      is_dragging_(false),
      font_(nullptr),
      is_hovered_(false),
      show_controls_(false),
      hover_start_time_(0),
      is_playing_(false),
      playback_callback_(nullptr) {
  InitGdiPlus();
  
  // Initialize button rects
  memset(&play_pause_button_rect_, 0, sizeof(RECT));
  memset(&prev_button_rect_, 0, sizeof(RECT));
  memset(&next_button_rect_, 0, sizeof(RECT));
}

DesktopLyricWindow::~DesktopLyricWindow() {
  Destroy();
  ShutdownGdiPlus();
}

bool DesktopLyricWindow::Create() {
  if (hwnd_ != nullptr) {
    return true;  // Window already exists
  }

  // Register window class
  WNDCLASSEX wc = {};
  wc.cbSize = sizeof(WNDCLASSEX);
  wc.style = CS_HREDRAW | CS_VREDRAW;
  wc.lpfnWndProc = WndProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  wc.lpszClassName = kWindowClassName;
  
  if (!RegisterClassEx(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    return false;
  }

  // Get screen size
  int screen_width = GetSystemMetrics(SM_CXSCREEN);
  int screen_height = GetSystemMetrics(SM_CYSCREEN);
  
  // Default position: center bottom
  int x = (screen_width - kWindowWidth) / 2;
  int y = screen_height - kWindowHeight - 100;

  // Create layered window
  hwnd_ = CreateWindowEx(
      WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
      kWindowClassName,
      L"Desktop Lyric",
      WS_POPUP,
      x, y, kWindowWidth, kWindowHeight,
      nullptr,
      nullptr,
      GetModuleHandle(nullptr),
      this);

  if (hwnd_ == nullptr) {
    return false;
  }

  // Save this pointer
  SetWindowLongPtr(hwnd_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));

  // Create font
  font_ = CreateFont(
      font_size_, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      ANTIALIASED_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
      L"Microsoft YaHei");

  return true;
}

void DesktopLyricWindow::Destroy() {
  if (hwnd_ != nullptr) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
  
  if (font_ != nullptr) {
    DeleteObject(font_);
    font_ = nullptr;
  }
}

void DesktopLyricWindow::Show() {
  if (hwnd_ != nullptr) {
    UpdateWindow();
    ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
  }
}

void DesktopLyricWindow::Hide() {
  if (hwnd_ != nullptr) {
    ShowWindow(hwnd_, SW_HIDE);
  }
}

bool DesktopLyricWindow::IsVisible() const {
  return hwnd_ != nullptr && IsWindowVisible(hwnd_);
}

void DesktopLyricWindow::SetLyricText(const std::wstring& text) {
  lyric_text_ = text;
  if (IsVisible()) {
    UpdateWindow();
  }
}

void DesktopLyricWindow::SetPosition(int x, int y) {
  if (hwnd_ != nullptr) {
    SetWindowPos(hwnd_, HWND_TOPMOST, x, y, 0, 0, 
                 SWP_NOSIZE | SWP_NOACTIVATE);
  }
}

void DesktopLyricWindow::GetPosition(int* x, int* y) {
  if (hwnd_ != nullptr) {
    RECT rect;
    GetWindowRect(hwnd_, &rect);
    *x = rect.left;
    *y = rect.top;
  }
}

void DesktopLyricWindow::SetFontSize(int size) {
  font_size_ = size;
  
  // Recreate font
  if (font_ != nullptr) {
    DeleteObject(font_);
  }
  
  font_ = CreateFont(
      font_size_, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      ANTIALIASED_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
      L"Microsoft YaHei");
  
  if (IsVisible()) {
    UpdateWindow();
  }
}

void DesktopLyricWindow::SetTextColor(DWORD color) {
  text_color_ = color;
  if (IsVisible()) {
    UpdateWindow();
  }
}

void DesktopLyricWindow::SetStrokeColor(DWORD color) {
  stroke_color_ = color;
  if (IsVisible()) {
    UpdateWindow();
  }
}

void DesktopLyricWindow::SetStrokeWidth(int width) {
  stroke_width_ = width;
  if (IsVisible()) {
    UpdateWindow();
  }
}

void DesktopLyricWindow::SetDraggable(bool draggable) {
  is_draggable_ = draggable;
}

void DesktopLyricWindow::SetMouseTransparent(bool transparent) {
  if (hwnd_ == nullptr) return;
  
  LONG exStyle = GetWindowLong(hwnd_, GWL_EXSTYLE);
  if (transparent) {
    exStyle |= WS_EX_TRANSPARENT;
  } else {
    exStyle &= ~WS_EX_TRANSPARENT;
  }
  SetWindowLong(hwnd_, GWL_EXSTYLE, exStyle);
}

void DesktopLyricWindow::SetSongInfo(const std::wstring& title, const std::wstring& artist, const std::wstring& album_cover) {
  song_title_ = title;
  song_artist_ = artist;
  album_cover_url_ = album_cover;
  if (IsVisible()) {
    UpdateWindow();
  }
}

void DesktopLyricWindow::SetPlaybackControlCallback(PlaybackControlCallback callback) {
  playback_callback_ = callback;
}

void DesktopLyricWindow::SetPlayingState(bool is_playing) {
  is_playing_ = is_playing;
  if (IsVisible() && show_controls_) {
    UpdateWindow();  // Refresh to show updated button icon
  }
}

int DesktopLyricWindow::GetControlPanelHeight() const {
  // Calculate height based on font size:
  // - Header area (song title + artist): ~70px
  // - Lyric area: font_size_ + padding (~20px)
  // - Button area: ~60px
  // - Bottom padding: ~10px
  return 70 + font_size_ + 20 + 60 + 10;
}

void DesktopLyricWindow::UpdateWindow() {
  if (hwnd_ == nullptr) return;

  // Determine current window height based on control panel state
  int current_height = show_controls_ ? GetControlPanelHeight() : kWindowHeight;

  // Create memory DC
  HDC hdc_screen = GetDC(nullptr);
  HDC hdc_mem = CreateCompatibleDC(hdc_screen);
  
  // Create 32-bit bitmap with dynamic height
  BITMAPINFO bmi = {};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = kWindowWidth;
  bmi.bmiHeader.biHeight = -current_height;  // Negative means top-down
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;
  
  void* bits = nullptr;
  HBITMAP hbm = CreateDIBSection(hdc_mem, &bmi, DIB_RGB_COLORS, &bits, nullptr, 0);
  HBITMAP hbm_old = (HBITMAP)SelectObject(hdc_mem, hbm);
  
  // Draw lyric with dynamic height
  DrawLyric(hdc_mem, kWindowWidth, current_height);
  
  // Update layered window with dynamic size
  POINT pt_src = {0, 0};
  SIZE size = {kWindowWidth, current_height};
  BLENDFUNCTION blend = {AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
  
  UpdateLayeredWindow(hwnd_, hdc_screen, nullptr, &size, hdc_mem, &pt_src,
                      0, &blend, ULW_ALPHA);
  
  // Cleanup
  SelectObject(hdc_mem, hbm_old);
  DeleteObject(hbm);
  DeleteDC(hdc_mem);
  ReleaseDC(nullptr, hdc_screen);
}

void DesktopLyricWindow::DrawLyric(HDC hdc, int width, int height) {
  // Use GDI+ to draw text (better anti-aliasing and stroke)
  Gdiplus::Graphics graphics(hdc);
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAlias);
  
  // Clear background (transparent)
  graphics.Clear(Gdiplus::Color(0, 0, 0, 0));
  
  // Draw control panel if hovered
  if (show_controls_) {
    DrawControlPanel(hdc, width, height);
    return;
  }
  
  if (lyric_text_.empty()) {
    return;
  }
  
  // Create font
  Gdiplus::FontFamily fontFamily(L"Microsoft YaHei");
  Gdiplus::Font font(&fontFamily, static_cast<Gdiplus::REAL>(font_size_), 
                     Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
  
  // Measure text size
  Gdiplus::RectF layoutRect(0, 0, static_cast<Gdiplus::REAL>(width), 
                             static_cast<Gdiplus::REAL>(height));
  Gdiplus::RectF boundRect;
  Gdiplus::StringFormat format;
  format.SetAlignment(Gdiplus::StringAlignmentCenter);
  format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
  
  graphics.MeasureString(lyric_text_.c_str(), -1, &font, layoutRect, &format, &boundRect);
  
  // Draw stroke (multiple draws to simulate stroke effect)
  if (stroke_width_ > 0) {
    Gdiplus::GraphicsPath path;
    Gdiplus::FontFamily fontFamilyPath(L"Microsoft YaHei");
    path.AddString(lyric_text_.c_str(), -1, &fontFamilyPath, 
                   Gdiplus::FontStyleBold, static_cast<Gdiplus::REAL>(font_size_),
                   layoutRect, &format);
    
    Gdiplus::Pen stroke_pen(Gdiplus::Color(
        (stroke_color_ >> 24) & 0xFF,  // A
        (stroke_color_ >> 16) & 0xFF,  // R
        (stroke_color_ >> 8) & 0xFF,   // G
        stroke_color_ & 0xFF           // B
    ), static_cast<Gdiplus::REAL>(stroke_width_));
    
    stroke_pen.SetLineJoin(Gdiplus::LineJoinRound);
    graphics.DrawPath(&stroke_pen, &path);
    
    // Fill text
    Gdiplus::SolidBrush text_brush(Gdiplus::Color(
        (text_color_ >> 24) & 0xFF,  // A
        (text_color_ >> 16) & 0xFF,  // R
        (text_color_ >> 8) & 0xFF,   // G
        text_color_ & 0xFF           // B
    ));
    graphics.FillPath(&text_brush, &path);
  } else {
    // No stroke, draw text directly
    Gdiplus::SolidBrush text_brush(Gdiplus::Color(
        (text_color_ >> 24) & 0xFF,
        (text_color_ >> 16) & 0xFF,
        (text_color_ >> 8) & 0xFF,
        text_color_ & 0xFF
    ));
    graphics.DrawString(lyric_text_.c_str(), -1, &font, layoutRect, &format, &text_brush);
  }
}

LRESULT CALLBACK DesktopLyricWindow::WndProc(HWND hwnd, UINT message,
                                              WPARAM wparam, LPARAM lparam) {
  DesktopLyricWindow* window = 
      reinterpret_cast<DesktopLyricWindow*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
  
  if (window == nullptr) {
    return DefWindowProc(hwnd, message, wparam, lparam);
  }
  
  switch (message) {
    case WM_LBUTTONDOWN: {
      POINT pt = {LOWORD(lparam), HIWORD(lparam)};
      bool button_clicked = false;
      
      if (window->show_controls_) {
        // Check if clicked on a button
        button_clicked = window->HandleButtonClick(pt);
      }
      
      // If not clicking a button and draggable, start dragging
      if (!button_clicked && window->is_draggable_) {
        window->is_dragging_ = true;
        window->drag_point_.x = pt.x;
        window->drag_point_.y = pt.y;
        SetCapture(hwnd);
      }
      return 0;
    }
    
    case WM_LBUTTONUP: {
      if (window->is_dragging_) {
        window->is_dragging_ = false;
        ReleaseCapture();
      }
      return 0;
    }
    
    case WM_MOUSEMOVE: {
      if (window->is_dragging_) {
        RECT rect;
        GetWindowRect(hwnd, &rect);
        
        int mouse_x = LOWORD(lparam);
        int mouse_y = HIWORD(lparam);
        
        int new_x = rect.left + (mouse_x - window->drag_point_.x);
        int new_y = rect.top + (mouse_y - window->drag_point_.y);
        
        SetWindowPos(hwnd, HWND_TOPMOST, new_x, new_y, 0, 0,
                     SWP_NOSIZE | SWP_NOACTIVATE);
      }
      
      // Track mouse hover
      if (!window->is_hovered_) {
        window->is_hovered_ = true;
        window->hover_start_time_ = GetTickCount();
        
        OutputDebugStringW(L"[DesktopLyric] Mouse entered, starting hover timer\n");
        
        // Start tracking mouse leave
        TRACKMOUSEEVENT tme = {};
        tme.cbSize = sizeof(TRACKMOUSEEVENT);
        tme.dwFlags = TME_LEAVE;
        tme.hwndTrack = hwnd;
        TrackMouseEvent(&tme);
        
        // Set timer to show controls after delay
        SetTimer(hwnd, 1, kHoverDelay, nullptr);
      }
      return 0;
    }
    
    case WM_MOUSELEAVE: {
      window->is_hovered_ = false;
      window->show_controls_ = false;
      window->hover_start_time_ = 0;
      KillTimer(hwnd, 1);
      
      // Get current window position
      RECT rect;
      GetWindowRect(hwnd, &rect);
      
      // Resize window back to lyric-only size (keep position)
      SetWindowPos(hwnd, HWND_TOPMOST, rect.left, rect.top, 
                   kWindowWidth, kWindowHeight,
                   SWP_NOACTIVATE);
      window->UpdateWindow();
      return 0;
    }
    
    case WM_TIMER: {
      if (wparam == 1 && window->is_hovered_ && !window->show_controls_) {
        window->show_controls_ = true;
        KillTimer(hwnd, 1);
        
        OutputDebugStringW(L"[DesktopLyric] Timer triggered, showing control panel\n");
        
        // Get current window position
        RECT rect;
        GetWindowRect(hwnd, &rect);
        
        // Calculate new Y position to expand downward
        // Keep top position the same, just increase height
        int current_y = rect.top;
        
        // Resize window to show control panel (expand downward)
        SetWindowPos(hwnd, HWND_TOPMOST, rect.left, current_y, 
                     kWindowWidth, window->GetControlPanelHeight(),
                     SWP_NOACTIVATE);
        window->UpdateWindow();
      }
      return 0;
    }
    
    case WM_DESTROY: {
      PostQuitMessage(0);
      return 0;
    }
  }
  
  return DefWindowProc(hwnd, message, wparam, lparam);
}

// Helper method implementations
bool DesktopLyricWindow::IsPointInRect(const POINT& pt, const RECT& rect) const {
  return pt.x >= rect.left && pt.x <= rect.right && 
         pt.y >= rect.top && pt.y <= rect.bottom;
}

bool DesktopLyricWindow::HandleButtonClick(const POINT& pt) {
  if (IsPointInRect(pt, prev_button_rect_)) {
    if (playback_callback_) playback_callback_("previous");
    return true;
  } else if (IsPointInRect(pt, play_pause_button_rect_)) {
    if (playback_callback_) playback_callback_("play_pause");
    return true;
  } else if (IsPointInRect(pt, next_button_rect_)) {
    if (playback_callback_) playback_callback_("next");
    return true;
  }
  return false;  // No button was clicked
}

void DesktopLyricWindow::DrawControlPanel(HDC hdc, int width, int height) {
  OutputDebugStringW(L"[DesktopLyric] Drawing control panel\n");
  
  Gdiplus::Graphics graphics(hdc);
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAlias);
  
  // Draw semi-transparent background
  Gdiplus::SolidBrush bg_brush(Gdiplus::Color(200, 30, 30, 30));  // Semi-transparent dark gray
  Gdiplus::RectF bg_rect(0, 0, static_cast<Gdiplus::REAL>(width), static_cast<Gdiplus::REAL>(height));
  graphics.FillRectangle(&bg_brush, bg_rect);
  
  // Draw rounded border
  Gdiplus::Pen border_pen(Gdiplus::Color(150, 255, 255, 255), 2.0f);
  Gdiplus::GraphicsPath path;
  float radius = 10.0f;
  Gdiplus::RectF rect(1, 1, static_cast<Gdiplus::REAL>(width - 2), static_cast<Gdiplus::REAL>(height - 2));
  path.AddArc(rect.X, rect.Y, radius * 2, radius * 2, 180, 90);
  path.AddArc(rect.X + rect.Width - radius * 2, rect.Y, radius * 2, radius * 2, 270, 90);
  path.AddArc(rect.X + rect.Width - radius * 2, rect.Y + rect.Height - radius * 2, radius * 2, radius * 2, 0, 90);
  path.AddArc(rect.X, rect.Y + rect.Height - radius * 2, radius * 2, radius * 2, 90, 90);
  path.CloseFigure();
  graphics.DrawPath(&border_pen, &path);
  
  // Draw song info
  Gdiplus::FontFamily fontFamily(L"Microsoft YaHei");
  Gdiplus::Font title_font(&fontFamily, 18, Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
  Gdiplus::Font artist_font(&fontFamily, 14, Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
  Gdiplus::SolidBrush text_brush(Gdiplus::Color(255, 255, 255, 255));
  
  // Song title
  if (!song_title_.empty()) {
    Gdiplus::RectF title_rect(20, 15, static_cast<Gdiplus::REAL>(width - 40), 25);
    Gdiplus::StringFormat format;
    format.SetAlignment(Gdiplus::StringAlignmentCenter);
    graphics.DrawString(song_title_.c_str(), -1, &title_font, title_rect, &format, &text_brush);
  }
  
  // Artist name
  if (!song_artist_.empty()) {
    Gdiplus::RectF artist_rect(20, 45, static_cast<Gdiplus::REAL>(width - 40), 20);
    Gdiplus::StringFormat format;
    format.SetAlignment(Gdiplus::StringAlignmentCenter);
    Gdiplus::SolidBrush artist_brush(Gdiplus::Color(200, 255, 255, 255));
    graphics.DrawString(song_artist_.c_str(), -1, &artist_font, artist_rect, &format, &artist_brush);
  }
  
  // Draw lyric text with original style (same as DrawLyric)
  if (!lyric_text_.empty()) {
    // Use user-configured font size and style
    Gdiplus::FontFamily lyricFontFamily(L"Microsoft YaHei");
    Gdiplus::Font lyric_font(&lyricFontFamily, static_cast<Gdiplus::REAL>(font_size_), 
                             Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
    // Dynamic lyric area height based on font size
    int lyric_area_height = font_size_ + 10;
    Gdiplus::RectF lyric_rect(20, 70, static_cast<Gdiplus::REAL>(width - 40), 
                               static_cast<Gdiplus::REAL>(lyric_area_height));
    Gdiplus::StringFormat format;
    format.SetAlignment(Gdiplus::StringAlignmentCenter);
    format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    
    // Draw with stroke effect (same as original lyric)
    if (stroke_width_ > 0) {
      Gdiplus::GraphicsPath lyric_path;
      lyric_path.AddString(lyric_text_.c_str(), -1, &lyricFontFamily, 
                           Gdiplus::FontStyleBold, static_cast<Gdiplus::REAL>(font_size_),
                           lyric_rect, &format);
      
      // Stroke pen with user-configured color
      Gdiplus::Pen lyric_stroke_pen(Gdiplus::Color(
          (stroke_color_ >> 24) & 0xFF,
          (stroke_color_ >> 16) & 0xFF,
          (stroke_color_ >> 8) & 0xFF,
          stroke_color_ & 0xFF
      ), static_cast<Gdiplus::REAL>(stroke_width_));
      lyric_stroke_pen.SetLineJoin(Gdiplus::LineJoinRound);
      graphics.DrawPath(&lyric_stroke_pen, &lyric_path);
      
      // Fill text with user-configured color
      Gdiplus::SolidBrush lyric_text_brush(Gdiplus::Color(
          (text_color_ >> 24) & 0xFF,
          (text_color_ >> 16) & 0xFF,
          (text_color_ >> 8) & 0xFF,
          text_color_ & 0xFF
      ));
      graphics.FillPath(&lyric_text_brush, &lyric_path);
    } else {
      // No stroke, draw text directly with user-configured color
      Gdiplus::SolidBrush lyric_text_brush(Gdiplus::Color(
          (text_color_ >> 24) & 0xFF,
          (text_color_ >> 16) & 0xFF,
          (text_color_ >> 8) & 0xFF,
          text_color_ & 0xFF
      ));
      graphics.DrawString(lyric_text_.c_str(), -1, &lyric_font, lyric_rect, &format, &lyric_text_brush);
    }
  }
  
  // Draw control buttons (position based on font size)
  int lyric_bottom = 70 + font_size_ + 20;  // After lyric area
  int button_y = lyric_bottom;
  int button_size = 40;
  int button_spacing = 60;
  int center_x = width / 2;
  
  // Previous button
  int prev_x = center_x - button_spacing - button_size / 2;
  prev_button_rect_.left = prev_x;
  prev_button_rect_.top = button_y;
  prev_button_rect_.right = prev_x + button_size;
  prev_button_rect_.bottom = button_y + button_size;
  
  Gdiplus::SolidBrush button_brush(Gdiplus::Color(180, 255, 255, 255));
  Gdiplus::Pen button_pen(Gdiplus::Color(255, 255, 255, 255), 2.0f);
  
  // Draw previous button (◀)
  graphics.FillEllipse(&button_brush, static_cast<Gdiplus::REAL>(prev_x), 
                       static_cast<Gdiplus::REAL>(button_y), 
                       static_cast<Gdiplus::REAL>(button_size), 
                       static_cast<Gdiplus::REAL>(button_size));
  Gdiplus::PointF prev_triangle[3] = {
    Gdiplus::PointF(static_cast<Gdiplus::REAL>(prev_x + button_size * 0.6f), 
                    static_cast<Gdiplus::REAL>(button_y + button_size * 0.3f)),
    Gdiplus::PointF(static_cast<Gdiplus::REAL>(prev_x + button_size * 0.6f), 
                    static_cast<Gdiplus::REAL>(button_y + button_size * 0.7f)),
    Gdiplus::PointF(static_cast<Gdiplus::REAL>(prev_x + button_size * 0.35f), 
                    static_cast<Gdiplus::REAL>(button_y + button_size * 0.5f))
  };
  Gdiplus::SolidBrush icon_brush(Gdiplus::Color(255, 30, 30, 30));
  graphics.FillPolygon(&icon_brush, prev_triangle, 3);
  
  // Play/Pause button
  int play_x = center_x - button_size / 2;
  play_pause_button_rect_.left = play_x;
  play_pause_button_rect_.top = button_y;
  play_pause_button_rect_.right = play_x + button_size;
  play_pause_button_rect_.bottom = button_y + button_size;
  
  graphics.FillEllipse(&button_brush, static_cast<Gdiplus::REAL>(play_x), 
                       static_cast<Gdiplus::REAL>(button_y), 
                       static_cast<Gdiplus::REAL>(button_size), 
                       static_cast<Gdiplus::REAL>(button_size));
  
  if (is_playing_) {
    // Draw pause icon (two vertical bars ⏸)
    int bar_width = static_cast<int>(button_size * 0.12f);
    int bar_height = static_cast<int>(button_size * 0.4f);
    int bar_y = button_y + static_cast<int>(button_size * 0.3f);
    int bar1_x = play_x + static_cast<int>(button_size * 0.32f);
    int bar2_x = play_x + static_cast<int>(button_size * 0.56f);
    
    Gdiplus::RectF bar1(static_cast<Gdiplus::REAL>(bar1_x), 
                        static_cast<Gdiplus::REAL>(bar_y),
                        static_cast<Gdiplus::REAL>(bar_width), 
                        static_cast<Gdiplus::REAL>(bar_height));
    Gdiplus::RectF bar2(static_cast<Gdiplus::REAL>(bar2_x), 
                        static_cast<Gdiplus::REAL>(bar_y),
                        static_cast<Gdiplus::REAL>(bar_width), 
                        static_cast<Gdiplus::REAL>(bar_height));
    graphics.FillRectangle(&icon_brush, bar1);
    graphics.FillRectangle(&icon_brush, bar2);
  } else {
    // Draw play triangle (▶)
    Gdiplus::PointF play_triangle[3] = {
      Gdiplus::PointF(static_cast<Gdiplus::REAL>(play_x + button_size * 0.38f), 
                      static_cast<Gdiplus::REAL>(button_y + button_size * 0.3f)),
      Gdiplus::PointF(static_cast<Gdiplus::REAL>(play_x + button_size * 0.38f), 
                      static_cast<Gdiplus::REAL>(button_y + button_size * 0.7f)),
      Gdiplus::PointF(static_cast<Gdiplus::REAL>(play_x + button_size * 0.68f), 
                      static_cast<Gdiplus::REAL>(button_y + button_size * 0.5f))
    };
    graphics.FillPolygon(&icon_brush, play_triangle, 3);
  }
  
  // Next button
  int next_x = center_x + button_spacing - button_size / 2;
  next_button_rect_.left = next_x;
  next_button_rect_.top = button_y;
  next_button_rect_.right = next_x + button_size;
  next_button_rect_.bottom = button_y + button_size;
  
  graphics.FillEllipse(&button_brush, static_cast<Gdiplus::REAL>(next_x), 
                       static_cast<Gdiplus::REAL>(button_y), 
                       static_cast<Gdiplus::REAL>(button_size), 
                       static_cast<Gdiplus::REAL>(button_size));
  // Draw next triangle (▶)
  Gdiplus::PointF next_triangle[3] = {
    Gdiplus::PointF(static_cast<Gdiplus::REAL>(next_x + button_size * 0.4f), 
                    static_cast<Gdiplus::REAL>(button_y + button_size * 0.3f)),
    Gdiplus::PointF(static_cast<Gdiplus::REAL>(next_x + button_size * 0.4f), 
                    static_cast<Gdiplus::REAL>(button_y + button_size * 0.7f)),
    Gdiplus::PointF(static_cast<Gdiplus::REAL>(next_x + button_size * 0.65f), 
                    static_cast<Gdiplus::REAL>(button_y + button_size * 0.5f))
  };
  graphics.FillPolygon(&icon_brush, next_triangle, 3);
}
