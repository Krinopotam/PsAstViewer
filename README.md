# PsAstViewer

![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue?logo=powershell)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey?logo=windows)
![License](https://img.shields.io/badge/License-Apache%202.0-blue)
![UI](https://img.shields.io/badge/UI-WinForms-orange)

**PsAstViewer** is a PowerShell module designed for convenient visualization and exploration of the PowerShell Abstract Syntax Tree (AST).  
It provides an interactive **WinForms-based** interface that allows you to inspect, navigate, and dynamically update the AST structure of PowerShell scripts.

> ⚠️ **Note:** This module works only on **Windows**, since it uses WinForms.  
> Minimum PowerShell version: **5.1**

---

## 📦 Installation

You can install **PsAstViewer** either from the **PowerShell Gallery** or directly from **GitHub**.

### 🏗️ Option 1 — From PowerShell Gallery

Run the following command in PowerShell (requires internet access):

```powershell
Install-Module PsAstViewer -Scope CurrentUser
```

Then import the module:

```powershell
Import-Module PsAstViewer
```

### 💾 Option 2 — From GitHub

1. Clone or download this repository:
   ```powershell
   git clone https://github.com/yourusername/PsAstViewer.git
   ```

2. Import the module manually:
   ```powershell
   Import-Module .\PsAstViewer\PsAstViewer.psd1
   ```

3. (Optional) To make the module available globally, copy the folder to one of the PowerShell module paths, for example:
   ```powershell
   $env:USERPROFILE\Documents\WindowsPowerShell\Modules\PsAstViewer
   ```

---

## 🚀 Usage

To launch the AST Viewer, run:

```powershell
Show-AstViewer -Path ".\example.ps1"
```

This will open a graphical window displaying the Abstract Syntax Tree of the specified PowerShell script.

---

## 🧩 Requirements

- **Operating System:** Windows only  
- **PowerShell:** Version 5.1 or higher  
- **Dependencies:** Built-in WinForms libraries (no external dependencies)

---

## 🖼️ Screenshot

Here is the PsAstViewer interface:

![AST Viewer UI](https://github.com/user-attachments/assets/1b7d6424-8c53-48c5-bd4d-f5ddb093c279)

## 🖥️ User Interface Overview

The application window consists of three main panels:

### 1. **AST Tree (Top-Left)**
A **TreeView** control displaying the hierarchical structure of AST nodes.  
Each node represents an element of the PowerShell script (such as a statement, expression, or parameter).

### 2. **AST Node Properties (Bottom-Left)**
Displays the **properties** of the currently selected AST node.  
- If a property is itself another AST node, you can **Ctrl + Click** (or use right click context menu) on it to jump directly to that node in the tree.  
- This allows for fast navigation between related elements of the syntax structure.

### 3. **Code View (Right)**
An **editable text box** showing the PowerShell source code.  
- When you select an AST node in the tree, the corresponding code region is **highlighted** in this view.  
- If you select another AST node via the properties panel, its code range is **additionally highlighted**, making overlapping regions visible.  
- When you **Ctrl + Click** (or use right click context menu) anywhere in the code editor, the viewer automatically determines which AST node corresponds to that position, selects it in the tree, and highlights its range in the code.  
- Use **Ctrl + F** to search.
- The status bar displays information about the token located at the current cursor position (current char index, token kind, flags)
- You can edit the script directly in the **Code View** pane — changes will trigger automatic AST regeneration.

### Shallow FindAll Result

PowerShell's `Ast.FindAll(predicate, searchNested: false)` is advertised as a *non-recursive* search,  
but in practice it still includes certain nested AST nodes due to the internal structure of the parser.

To inspect the exact output of `FindAll(false)` for any specific AST node:

1. Select the node in the AST Tree.  
2. Right-click to open the context menu.  
3. Choose **Shallow FindAll Result**.

This displays the precise list of AST nodes that PowerShell considers “non-nested” for the selected node,
allowing you to understand how the parser actually interprets shallow traversal in this context.

---

## ⚙️ Technical Details

PsAstViewer internally uses the PowerShell parser from  
`System.Management.Automation.Language.Parser`  
to parse scripts and construct their Abstract Syntax Trees.  
The visualization is dynamically generated based on the resulting AST objects and their properties.

---

## 📄 License

This project is distributed under the **Apache License 2.0**.  
See the [LICENSE](https://github.com/Krinopotam/PsAstViewer/blob/master/LICENSE) file for details.
