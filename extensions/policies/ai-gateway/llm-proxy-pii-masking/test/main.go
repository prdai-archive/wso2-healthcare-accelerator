package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/joho/godotenv"
	"github.com/openai/openai-go/v3"
	"github.com/openai/openai-go/v3/option"
)

// Each sample makes the model repeat the PII back: OpenAI only sees <<OPENMED_PHI_...>> placeholders, restored below.
var samples = []string{
	"Patient Sarah Johnson (DOB 03/15/1985), MRN 4872910, phone 415-555-0123, " +
		"email sarah.johnson@example.com. Write a one-sentence appointment confirmation " +
		"addressed to the patient that repeats their name, phone number and email exactly as given.",
	"Dr. Emily Chen is referring patient Marcus Webb (SSN 523-44-1987) to cardiology. " +
		"Draft a one-line referral note naming both the doctor and the patient.",
	"Reschedule the follow-up for Anita Kapoor, contact number 020-7946-0958, to next Tuesday. " +
		"Reply with a single confirmation sentence that includes her name and number.",
}

func main() {
	err := godotenv.Load()
	if err != nil {
		log.Fatal("Error loading .env file")
	}
	httpClient := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		},
	}
	client := openai.NewClient(
		option.WithHTTPClient(httpClient),
		option.WithHeader("ApiKey", os.Getenv("OPENAI_API_KEY")),
	)
	for i, prompt := range samples {
		fmt.Printf("sample %d/%d\n", i+1, len(samples))
		fmt.Println("prompt: " + prompt)
		started := time.Now()
		res, err := client.Chat.Completions.New(context.TODO(), openai.ChatCompletionNewParams{
			Model: "gpt-5-nano",
			Messages: []openai.ChatCompletionMessageParamUnion{
				openai.UserMessage(prompt),
			},
		})
		if err != nil {
			log.Fatal(err.Error())
		}
		fmt.Println("reply : " + res.Choices[0].Message.Content)
		fmt.Printf("took  : %s\n\n", time.Since(started).Round(time.Millisecond))
	}
	fmt.Println("`make logs` shows what OpenAI actually saw — placeholders only.")
}
