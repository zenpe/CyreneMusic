#ifndef RUNNER_DESKTOP_LYRIC_WINDOW_H_
#define RUNNER_DESKTOP_LYRIC_WINDOW_H_

#include <windows.h>
#include <string>
#include <memory>
#include <functional>

// Desktop lyric window class
class DesktopLyricWindow {
 public:
  DesktopLyricWindow();
  ~DesktopLyricWindow();

  // Create desktop lyric window
  bool Create();
  
  // Destroy window
  void Destroy();
  
  // Show/Hide window
  void Show();
  void Hide();
  bool IsVisible() const;
  
  // Set lyric text
  void SetLyricText(const std::wstring& text);
  
  // Set window position
  void SetPosition(int x, int y);
  
  // Get window position
  void GetPosition(int* x, int* y);
  
  // Set font size
  void SetFontSize(int size);
  
  // Set text color (ARGB format)
  void SetTextColor(DWORD color);
  
  // Set stroke color (ARGB format)
  void SetStrokeColor(DWORD color);
  
  // Set stroke width
  void SetStrokeWidth(int width);
  
  // Set draggable
  void SetDraggable(bool draggable);
  
  // Set mouse transparent
  void SetMouseTransparent(bool transparent);
  
  // Set song info (title, artist, album cover URL)
  void SetSongInfo(const std::wstring& title, const std::wstring& artist, const std::wstring& album_cover);
  
  // Set playback control callback
  using PlaybackControlCallback = std::function<void(const std::string& action)>;
  void SetPlaybackControlCallback(PlaybackControlCallback callback);
  
  // Set playing state (for play/pause button icon)
  void SetPlayingState(bool is_playing);
  
  // Get window handle
  HWND GetHandle() const { return hwnd_; }

 private:
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  
  // Update window display
  void UpdateWindow();
  
  // Draw lyric to memory DC
  void DrawLyric(HDC hdc, int width, int height);
  
  HWND hwnd_;
  std::wstring lyric_text_;
  std::wstring song_title_;
  std::wstring song_artist_;
  std::wstring album_cover_url_;
  int font_size_;
  DWORD text_color_;
  DWORD stroke_color_;
  int stroke_width_;
  bool is_draggable_;
  bool is_dragging_;
  POINT drag_point_;
  HFONT font_;
  
  // Control panel state
  bool is_hovered_;
  bool show_controls_;
  DWORD hover_start_time_;
  bool is_playing_;  // Current playback state
  
  // Button hit test areas
  RECT play_pause_button_rect_;
  RECT prev_button_rect_;
  RECT next_button_rect_;
  
  // Playback control callback
  PlaybackControlCallback playback_callback_;
  
  // Helper methods
  bool IsPointInRect(const POINT& pt, const RECT& rect) const;
  void DrawControlPanel(HDC hdc, int width, int height);
  bool HandleButtonClick(const POINT& pt);  // Returns true if a button was clicked
  int GetControlPanelHeight() const;  // Dynamic height based on font size
};

#endif  // RUNNER_DESKTOP_LYRIC_WINDOW_H_
