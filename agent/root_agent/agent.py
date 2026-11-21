import base64

from google.adk.agents import Agent
from k8s_agent_sandbox import SandboxClient


def run_spreadsheet_analysis(code: str) -> str:
    """Runs a complete Python script inside an isolated GKE Agent Sandbox and returns its output.

    Use it for pandas analysis of spreadsheet or CSV data. Print every result you need.
    """
    encoded = base64.b64encode(code.encode()).decode()
    command = f"python3 -c \"import base64; exec(base64.b64decode('{encoded}').decode())\""
    with SandboxClient(template_name="python-runtime-template", namespace="default") as sandbox:
        result = sandbox.run(command)
    if result.stderr:
        return f"Error: {result.stderr}"
    return result.stdout


root_agent = Agent(
    name="SpreadsheetAnalyst",
    model="gemini-3.8-flash",
    instruction="""
    You are an expert data analyst. When a user asks you to analyse spreadsheet or CSV data:
    1. Work out what pandas code answers the question.
    2. Write one complete Python script that loads the data and prints the results.
    3. Run it with the run_spreadsheet_analysis tool. It executes in an isolated GKE sandbox.
    4. Summarise the answer clearly from the tool's output.

    If the user gives a file path, assume it is available in the sandbox, or load the data from a URL.
    """,
    tools=[run_spreadsheet_analysis],
)
