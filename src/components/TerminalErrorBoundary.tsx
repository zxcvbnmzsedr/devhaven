import { Component, type ErrorInfo, type ReactNode } from "react";

type Props = {
  children: ReactNode;
  onReset?: () => void;
};

type State = {
  error: Error | null;
};

class TerminalErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error("终端工作区渲染失败", error, info.componentStack);
  }

  handleReset = () => {
    this.setState({ error: null });
    this.props.onReset?.();
  };

  render() {
    if (!this.state.error) {
      return this.props.children;
    }

    return (
      <div className="flex h-full flex-col items-center justify-center gap-4 bg-[#171717] p-8 text-white">
        <div className="text-lg font-semibold text-red-400">终端工作区加载失败</div>
        <pre className="max-h-[300px] max-w-[600px] overflow-auto rounded-lg bg-[#0d0d0d] p-4 text-[13px] text-red-300">
          {this.state.error.message}
          {this.state.error.stack ? `\n\n${this.state.error.stack}` : ""}
        </pre>
        <button
          type="button"
          className="rounded-md border border-[rgba(255,255,255,0.15)] px-4 py-2 text-[13px] font-semibold text-white transition-colors hover:bg-[rgba(255,255,255,0.1)]"
          onClick={this.handleReset}
        >
          返回主界面
        </button>
      </div>
    );
  }
}

export default TerminalErrorBoundary;
