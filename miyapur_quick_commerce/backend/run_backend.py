import uvicorn

if __name__ == "__main__":
    print("Starting Miyapur Quick Commerce Backend on https://flash-fresh.onrender.com ...")
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=False)
